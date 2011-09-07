package Amling::GRD::Utils;

use strict;
use warnings;

sub log_commits
{
    my $args = shift;
    my $cb = shift;

    # argghwtf, why can't I get this shit all unambiguously parsable in one
    # invocation of git log?
    open(my $fh, '-|', 'git', 'log', '--format=%H:%P', @$args) || die "Cannot open git log: $!";
    while(my $line = <$fh>)
    {
        chomp $line;
        if($line =~ /^(.*):(.*)$/)
        {
            my ($commit, $parents) = ($1, $2);

            if(length($commit) != 40)
            {
                die "Bad commit: $commit";
            }

            my @parents;
            for my $parent (split(/ /, $parents))
            {
                if(length($parent) != 40)
                {
                    die "Bad parent: $parent";
                }
                push @parents, $parent;
            }

            open(my $fh2, '-|', 'git', 'log', '--format=%B', "-1", $commit) || die "Cannot open git log: $!";
            my $body = "";
            while(my $line2 = <$fh2>)
            {
                chomp $line2;
                $body .= "$line2\n";
            }
            # ugh, fucking dumb -- one is us the other is git spooging an extra for no apparent reason
            chomp $body;
            chomp $body;
            close($fh2) || die "Cannot close git log: $!";

            $cb->({'hash' => $commit, 'parents' => \@parents, 'msg' => $body});
        }
    }
    close($fh) || die "Cannot close git log: $!";
}

sub convert_commitlike
{
    my $commitlike = shift;

    open(my $fh, '-|', 'git', 'log', '-1', $commitlike, '--pretty=format:%H') || die "Cannot open log $commitlike: $!";
    my $commit = <$fh> || die "Could not read head commit for $commitlike";
    chomp $commit;
    if($commit !~ /^([0-9a-f]{40})$/)
    {
        die "Bad head commit for $commitlike: $commit";
    }
    close($fh) || die "Cannot open log $commitlike: $!";

    return $commit;
}

sub is_clean
{
    my ($dirtyness, $message) = get_dirtyness();
    return ($dirtyness ? 0 : 1);
}

sub get_dirtyness
{

    if(system("git", "diff", "--quiet"))
    {
        return (2, "There are differences between the index and the working tree.");
    }

    {
        my $fail = 0;
        open(my $fh, "-|", "git", "ls-files", "-u");
        while(<$fh>)
        {
            $fail = 1;
        }
        close($fh);
        if($fail)
        {
            return (2, "There are unmerged files in the index.");
        }
    }

    # TODO: doesn't catch untracked files... (?)
    if(system("git", "diff", "--cached", "--quiet"))
    {
        return (1, "There are differences between HEAD and the index.");
    }

    return 0;
}

sub run_shell
{
    my $first_shell = shift;
    my $allow_index = shift;
    my $allow_wtree = shift;

    my $shell = $ENV{'SHELL'} || '/bin/sh';
    my $grd_level = ($ENV{'GRD_LEVEL'} || 0);

    EDITLOOP:
    while(1)
    {
        if($first_shell)
        {
            {
                local $ENV{'GRD_LEVEL'} = ($grd_level + 1);
                print "GRD level: " . ($grd_level + 1) . "\n";
                system($shell);
            }
        }
        else
        {
            $first_shell = 1;
        }

        my $fail;
        my ($dirtyness, $message) = get_dirtyness();
        if(!$allow_index && $dirtyness >= 1)
        {
            $fail = $message;
        }
        if(!$allow_wtree && $dirtyness >= 2)
        {
            $fail = $message;
        }

        if(!$fail)
        {
            return;
        }

        # TODO: extract menu util
        while(1)
        {
            print "$fail\n";
            print "What should I do?\n";
            print "s - run a shell\n";
            print "q - abort entire rebase\n";
            print "> ";
            my $ans = <>;
            chomp $ans;

            if($ans eq "q")
            {
                print "Giving up.\n";
                exit 1;
            }
            if($ans eq "s")
            {
                next EDITLOOP;
            }

            print "Not an option: $ans\n";
        }
    }
}

sub run
{
    my @cmd = @_;

    print "Running: " . join(", ", @cmd) . "...\n";

    return (system(@cmd) == 0);
}

sub escape_msg
{
    my $msg = shift;

    $msg =~ s/\\/\\\\/g;
    $msg =~ s/\n/\\n/g;

    return $msg;
}

sub unescape_msg
{
    my $msg = shift;

    $msg =~ s/\\n/\n/g;
    $msg =~ s/\\\\/\\/g;

    return $msg;
}

1;
