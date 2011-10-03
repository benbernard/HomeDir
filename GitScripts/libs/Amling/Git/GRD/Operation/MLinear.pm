package Amling::Git::GRD::Operation::MLinear;

use strict;
use warnings;

use Amling::Git::GRD::Utils;
use Amling::Git::Utils;

# TODO: configurable or scoped better (in particular multiple mlinears will probably end up sad)
our $PREFIX = "INTERNAL";

# TODO: think hard about whether or not peephole optimization will clean up this mess

# TODO: peephole optimizers need to understand comment branch comments (I think this only blocks load/save pair which is useless anyway)
# TODO: peephole optimization for load/save pair (alias, ugh, this is only for 1-parent merge, fuck it)
# Ugh, consider:
#
# ...
# save alias1
# ...
# load alias1
# <implicit merge of single useful branch>
# # branch xxx
# save alias2
# ...
# load alias1
# ...
# load alias2
# ...
# load alias2
# ...
#
# The xxx branch comment should probably get moved to above save alias1?  But
# that looks funny and we probably shouldn't rename alias1 due to use
# elsewhere...  Thankfully I think this is only screwed up in 1-parent merges.

sub simple_handler
{
    my $s = shift;

    my ($base, $branch);
    if($s =~ /^(?:simple|S):([^,]*)(?:,([^,]*))?$/)
    {
        $base = $1;
        $branch = $2;
    }
    else
    {
        return;
    }

    my $head_branch = undef;
    {
        open(my $fh, '-|', 'git', 'symbolic-ref', '-q', 'HEAD') || die "Cannot open git symbolic-ref: $!";
        while(my $line = <$fh>)
        {
            chomp $line;
            if($line =~ /^refs\/heads\/(.*)$/)
            {
                $head_branch = $1;
            }
        }
        close($fh); # do not die, if HEAD is detached this fails, stupid fucking no good way to figure that out
    }

    my %branch_commands;
    my %commit_commands;
    my @targets;

    if(defined($branch))
    {
        # we only place this branch, as head (even if it wasn't head before)
        my $branch_commit = Amling::Git::Utils::convert_commitlike($branch);
        push @{$branch_commands{$branch} ||= []}, "head $branch";
        push @targets, $branch_commit;
    }
    else
    {
        # we weren't given a branch, what is HEAD's deal?
        if(defined($head_branch))
        {
            # ah, it's a branch, we place that
            my $branch_commit = Amling::Git::Utils::convert_commitlike($head_branch);
            push @{$branch_commands{$head_branch} ||=[]}, "head $head_branch";
            push @targets, $branch_commit;
        }
        else
        {
            # it's detached, we place a detached head at the SHA1
            my $head_commit = Amling::Git::Utils::convert_commitlike("HEAD");
            push @{$commit_commands{$head_commit} ||= []}, "head";
            push @targets, $head_commit;
        }
    }

    my $script = handle_common([$base], \%branch_commands, \%commit_commands, \@targets);

    my $latest_base = Amling::Git::Utils::convert_commitlike($base);

    return ($latest_base, $script);
}

sub multiple_handler
{
    my $s = shift;

    my @pieces;
    if($s =~ /^(?:multiple|M):(.*)$/)
    {
        @pieces = split(/,/, $1);
    }
    else
    {
        return;
    }

    my $head_branch = undef;
    {
        open(my $fh, '-|', 'git', 'symbolic-ref', '-q', 'HEAD') || die "Cannot open git symbolic-ref: $!";
        while(my $line = <$fh>)
        {
            chomp $line;
            if($line =~ /^refs\/heads\/(.*)$/)
            {
                $head_branch = $1;
            }
        }
        close($fh); # do not die, if HEAD is detached this fails, stupid fucking no good way to figure that out
    }

    my %branch_commands;
    my %commit_commands;
    my @targets;
    my @bases;
    my @trees;
    my $onto;

    for my $piece (@pieces)
    {
        if($piece =~ /^-(.*)$/)
        {
            push @bases, $1;
        }
        elsif($piece =~ /^O:(.*)$/)
        {
            push @bases, $1;
            $onto = $1;
        }
        elsif($piece =~ /^\+(.*)$/)
        {
            my $branch = $1;
            my $branch_commit = Amling::Git::Utils::convert_commitlike($branch);
            push @{$branch_commands{$branch} ||= []}, "branch $branch";
            push @targets, $branch_commit;
        }
        elsif($piece =~ /^H:(.*)$/)
        {
            my $branch = $1;
            my $branch_commit = Amling::Git::Utils::convert_commitlike($branch);
            push @{$branch_commands{$branch} ||= []}, "head $branch";
            push @targets, $branch_commit;
        }
        elsif($piece =~ /^H$/)
        {
            if(defined($head_branch))
            {
                my $head_commit = Amling::Git::Utils::convert_commitlike("HEAD");
                push @{$branch_commands{$head_branch} ||= []}, "head $head_branch";
                push @targets, $head_commit;
            }
            else
            {
                my $head_commit = Amling::Git::Utils::convert_commitlike("HEAD");
                push @{$commit_commands{$head_commit} ||= []}, "head";
                push @targets, $head_commit;
            }
        }
        elsif($piece =~ /^T:(.*)$/)
        {
            push @trees, $1;
        }
        else
        {
            die "Unintelligible piece: $piece";
        }
    }

    my %maximal_tree_commits;
    for my $tree (@trees)
    {
        # dump out upstream section
        my @tree_commits;
        my %tree_commits;
        my $cb = sub
        {
            my $h = shift;
            push @tree_commits, $h;
            $tree_commits{$h->{'hash'}} = 1;
        };
        Amling::Git::Utils::log_commits([(map { "^$_" } @bases), $tree], $cb);

        # now find those that have no parents in the upstream section (all i.e.  parents in the base)
        for my $h (@tree_commits)
        {
            my $maximal = 1;
            for my $p (@{$h->{'parents'}})
            {
                if($tree_commits{$p})
                {
                    $maximal = 0;
                    last;
                }
            }
            if($maximal)
            {
                $maximal_tree_commits{$h->{'hash'}} = 1;
            }
        }
    }

    # now iterate over branches that contain each maximal tree commit
    for my $commit (keys(%maximal_tree_commits))
    {
        open(my $fh, '-|', 'git', 'branch', '--contains', $commit) || die "Cannot open list branches containing $commit: $!";
        while(my $line = <$fh>)
        {
            chomp $line;

            $line =~ s/^..//;

            # this BS probably won't happen but let's be sure
            next if($line eq "(no branch)");

            my $branch = $line;

            if(!$branch_commands{$branch})
            {
                # and we haven't included it yet, do so
                my $branch_commit = Amling::Git::Utils::convert_commitlike($branch);
                push @{$branch_commands{$branch} = []}, "branch $branch";
                push @targets, $branch_commit;
            }
        }
        close($fh) || die "Cannot close list branches containing $commit: $!";
    }

    my $script = handle_common(\@bases, \%branch_commands, \%commit_commands, \@targets);

    my $latest_base = defined($onto) ? Amling::Git::Utils::convert_commitlike($onto) : undef;

    return ($latest_base, $script);
}

sub handle_common
{
    my $bases = shift;
    my $branch_commands = shift;
    my $commit_commands = shift;
    my $targets = shift;

    my %commit_branch_1;
    {
        open(my $fh, '-|', 'git', 'show-ref') || die "Cannot open git show-ref: $!";
        while(my $line = <$fh>)
        {
            if($line =~ /^([0-9a-f]{40}) (.*)$/)
            {
                my ($commit, $ref) = ($1, $2);
                if($ref =~ /^refs\/heads\/(.*)$/)
                {
                    $commit_branch_1{$commit}->{$1} = 1;
                }
            }
            else
            {
                die "Bad line: $line";
            }
        }
        close($fh) || die "Cannot close git show-ref: $!";
    }

    my %commits;
    my %parents;
    my %subjects;
    my $cb = sub
    {
        my $h = shift;
        my $commit = $h->{'hash'};

        $commits{$commit} = 1;
        $parents{$commit} = $h->{'parents'};
        $subjects{$commit} = $h->{'msg'};
    };
    Amling::Git::Utils::log_commits([(map { "^$_" } @$bases), keys(%$branch_commands), keys(%$commit_commands)], $cb);

    my @lines;
    push @lines, "save $PREFIX-base";
    my %built;
    for my $target (@$targets)
    {
        my ($contributes, @script) = build($target, \%commits, \%built, \%parents, \%subjects, $commit_commands, \%commit_branch_1, $branch_commands);
        if($contributes)
        {
            push @lines, @script;
        }
    }

    while(1)
    {
        my $progress = 0;
        for my $opt (\&peephole_useless_save, \&peephole_useless_sl_pair)
        {
            my $progress1;
            ($progress1, @lines) = $opt->(@lines);
            if($progress1)
            {
                $progress = 1;
            }
        }
        last unless($progress);
    }

    return \@lines;
}

Amling::Git::GRD::Operation::add_operation(\&simple_handler);
Amling::Git::GRD::Operation::add_operation(\&multiple_handler);

sub build
{
    my $target = shift;
    my $commits = shift;
    my $built = shift;
    my $parents = shift;
    my $subjects = shift;
    my $commit_commands = shift;
    my $commit_branch_1 = shift;
    my $branch_commands = shift;

    # asked to build something in base
    if(!$commits->{$target})
    {
        return 0;
    }

    # already built, and it was relevant (but no additional script)
    if($built->{$target})
    {
        return 1;
    }

    my @mparents = @{$parents->{$target}};

    my @ret;

    if(@mparents == 1)
    {
        my ($contributes, @script) = build($mparents[0], $commits, $built, $parents, $subjects, $commit_commands, $commit_branch_1, $branch_commands);

        if($contributes)
        {
            # non-merge built on a real commit
            push @ret, @script;
            push @ret, "load $PREFIX-" . $mparents[0];
        }
        else
        {
            # non-merge built on a dead commit, just build off base
            push @ret, "load $PREFIX-base";
        }

        push @ret, "pick $target # " . Amling::Git::GRD::Utils::escape_msg($subjects->{$target});
    }
    else
    {
        my @targets;

        for my $parent (@mparents)
        {
            my ($contributes, @script) = build($parent, $commits, $built, $parents, $subjects, $commit_commands, $commit_branch_1, $branch_commands);

            if($contributes)
            {
                push @ret, @script;
                push @targets, $parent;
            }
        }

        if(@targets == 0)
        {
            return 0;
        }

        if(@targets == 1)
        {
            push @ret, "load $PREFIX-" . $targets[0];
        }
        else
        {
            push @ret, "merge " . join(" ", map { "$PREFIX-$_" } @targets);
        }
    }

    push @ret, @{$commit_commands->{$target} || []};

    for my $branch (sort(keys(%{$commit_branch_1->{$target} || {}})))
    {
        my $commands = $branch_commands->{$branch};
        if($commands)
        {
            push @ret, @$commands;
        }
        else
        {
            push @ret, "# branch $branch";
        }
    }

    push @ret, "save $PREFIX-$target";
    $built->{$target} = 1;

    return (1, @ret);
}

sub peephole_useless_save
{
    my @lines = @_;

    my %loaded;

    for my $line (@lines)
    {
        if($line =~ /^load (.*)$/)
        {
            $loaded{$1} = 1;
        }
        elsif($line =~ /^merge (.*)$/)
        {
            for my $name (split(/ /, $1))
            {
                $loaded{$name} = 1;
            }
        }
    }

    my @lines2;
    my $progress = 0;
    for my $line (@lines)
    {
        if($line =~ /^save (.*)$/)
        {
            my $name = $1;
            if(!$loaded{$name})
            {
                $progress = 1;
                next;
            }
        }
        push @lines2, $line;
    }

    return ($progress, @lines2);
}

sub peephole_useless_sl_pair
{
    my @lines = @_;

    my @lines2;
    my $progress = 0;
    my $at = undef;
    for my $line (@lines)
    {
        if($line =~ /^load (.*)$/)
        {
            if(defined($at) && $at eq $1)
            {
                $progress = 1;
                next;
            }
        }
        if($line =~ /^save (.*)$/)
        {
            $at = $1;
        }
        else
        {
            $at = undef;
        }
        push @lines2, $line;
    }

    return ($progress, @lines2);
}

1;
