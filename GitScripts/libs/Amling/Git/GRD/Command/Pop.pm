package Amling::Git::GRD::Command::Pop;

use strict;
use warnings;

use Amling::Git::GRD::Command;
use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Utils;

use base 'Amling::Git::GRD::Command::Simple';

sub name
{
    return "pop";
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
        die "Empty commit stack popped";
    }

    Amling::Git::GRD::Utils::run("git", "checkout", $commit) || die "Cannot checkout $commit";
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
