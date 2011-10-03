package Amling::Git::GRD::Command::FSplatter;

use strict;
use warnings;

use Amling::Git::GRD::Command;
use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Utils;
use File::Temp ('tempfile');

use base 'Amling::Git::GRD::Command::Simple';

sub name
{
    return "fsplatter";
}

sub args
{
    return 0;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;

    my $commit = pop @{$ctx->get('commit-stack', [])};
    if(!defined($commit))
    {
        die "Empty commit stack splattered";
    }

    my $ccommit;
    {
        open(my $fh, '-|', 'git', 'log', "$commit..", "--pretty=format:%H") || die "Cannot open git log: $!";
        while(my $l = <$fh>)
        {
            if($l =~ /^([0-9a-f]{40})$/)
            {
                # we take the last
                $ccommit = $1;
            }
        }
        close($fh) || die "Cannot close git log: $!";

        if(!defined($ccommit))
        {
            die "Couldn't find comment commit for fsplatter?";
        }
    }

    Amling::Git::GRD::Utils::run("git", "reset", "--soft", $commit) || die "Cannot soft reset to $commit";
    Amling::Git::GRD::Utils::run("git", "commit", "-C", $ccommit) || die "Cannot commit?";
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
