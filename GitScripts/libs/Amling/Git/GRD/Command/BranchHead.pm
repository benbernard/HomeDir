package Amling::Git::GRD::Command::BranchHead;

use strict;
use warnings;

use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Command;
use Amling::Git::Utils;

use base 'Amling::Git::GRD::Command::Simple';

sub name
{
    return "head";
}

sub args
{
    return 1;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;
    my $branch = shift;

    $ctx->get('branches', {})->{$branch} = Amling::Git::Utils::convert_commitlike('HEAD');
    $ctx->set('head', [1, $branch]);
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
