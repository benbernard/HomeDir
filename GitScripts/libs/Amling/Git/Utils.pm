package Amling::Git::Utils;

use strict;
use warnings;

sub find_root
{
    my $optional = shift;
    my $fh;
    # !@#$ no silent mode
    if(!open($fh, 'git rev-parse --show-toplevel 2> /dev/null |'))
    {
        if($optional)
        {
            return undef;
        }
        else
        {
            die "Cannot open git rev-parse --show-toplevel: $!";
        }
    }
    my $line = <$fh>;
    if(!close($fh))
    {
        if($optional)
        {
            return undef;
        }
        else
        {
            die "Cannot close git rev-parse --show-toplevel: $!";
        }
    }
    chomp $line;
    return $line;
}

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

1;
