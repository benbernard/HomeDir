package Amling::GRD::Command::BranchHead;

use strict;
use warnings;

use Amling::GRD::Command;
use Amling::GRD::Command::Simple;
use Amling::GRD::Utils;

use base 'Amling::GRD::Command::Simple';

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

    $ctx->get('branches', {})->{$branch} = Amling::GRD::Utils::convert_commitlike('HEAD');
    $ctx->set('head', [1, $branch]);
}

Amling::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
