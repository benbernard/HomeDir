package Amling::GRD::Operation::Tree;

use strict;
use warnings;

use Amling::GRD::Utils;

# TODO: OMFG, HEAD

sub handler
{
    my $s = shift;

    my ($base, $tree);
    if($s =~ /^(?:tree|T):([^,]*)(?:,([^,]*))?$/)
    {
        $base = $1;
        $tree = $2;
        if(!defined($tree))
        {
            $tree = "HEAD";
        }
    }
    else
    {
        return;
    }

    my $first_tree;
    my $last_base;
    {
        open(my $fh, '-|', 'git', 'log', "$base..$tree", '--pretty=format:%H:%P') || die "Cannot open top git log: $!";
        while(my $line = <$fh>)
        {
            chomp $line;
            if($line =~ /^([0-9a-f]{40}):([0-9a-f]{40})$/)
            {
                if(!defined($last_base))
                {
                    $first_tree = $1;
                    $last_base = $2;
                }
                elsif($1 eq $last_base)
                {
                    $first_tree = $last_base;
                    $last_base = $2;
                }
            }
            else
            {
                die "Bad line: $line";
            }
        }
        close($fh) || die "Cannot close top git log: $!";
        defined($last_base) || die "Could not find last base commit";
    }

    my $latest_base = Amling::GRD::Utils::convert_commitlike($base);

    my @tree_branches;
    {
        open(my $fh, '-|', 'git', 'branch', '--contains', $first_tree) || die "Cannot open list branches containing $first_tree: $!";
        while(my $line = <$fh>)
        {
            chomp $line;

            $line =~ s/^..//;

            # this BS probably won't happen but let's be sure
            next if($line eq "(no branch)");

            push @tree_branches, $line;
        }
        close($fh) || die "Cannot close list branches containing $last_base: $!";
    }

    my %branch_commits;
    my %commit_branches;
    {
        for my $branch (@tree_branches)
        {
            my $commit = Amling::GRD::Utils::convert_commitlike($branch);

            $branch_commits{$branch} = $commit;
            push @{$commit_branches{$commit} ||= []}, $branch;
        }
    }

    my %commits;
    my %children;
    my %parents;
    my %subject;
    {
        open(my $fh, '-|', 'git', 'log', (map { "$last_base..$_" } @tree_branches), '--pretty=format:%H:%P:%s') || die "Cannot open full tree log";
        while(my $line = <$fh>)
        {
            chomp $line;
            if($line =~ /^([0-9a-f]{40}):([0-9a-f]{40}):(.*)$/)
            {
                my ($child, $parent, $subject) = ($1, $2, $3);
                $parents{$child} = $parent;
                ($children{$parent} ||= {})->{$child} = 1;
                $subject{$child} = $subject;
                $commits{$child} = 1;
            }
            else
            {
                die "Bad line: $line";
            }
        }
        close($fh) || die "Cannot close full tree log";
    }

    return ($latest_base, [dump_tree(0, $first_tree, \%subject, \%commit_branches, \%children)]);
}

Amling::GRD::Operation::add_operation(\&handler);

sub dump_tree
{
    my ($indent, $root, $subjects, $commit_branches, $children) = @_;

    my @ret;

    push @ret, (("   " x $indent) . "pick " . $root . " # " . Amling::GRD::Utils::escape_msg($subjects->{$root}));
    my @branches = @{$commit_branches->{$root} || []};
    for my $branch (@branches)
    {
        push @ret, (("   " x $indent) . "branch " . $branch);
    }

    my @children = sort(keys(%{$children->{$root}}));

    if(@children == 0)
    {
    }
    elsif(@children == 1)
    {
        push @ret, dump_tree($indent, $children[0], $subjects, $commit_branches, $children);
    }
    else
    {
        for my $child (sort(keys(%{$children->{$root}})))
        {
            push @ret, (("   " x $indent) . "push");
            push @ret, dump_tree($indent + 1, $child, $subjects, $commit_branches, $children);
            push @ret, (("   " x $indent) . "pop");
        }
    }

    return @ret;
}

1;
