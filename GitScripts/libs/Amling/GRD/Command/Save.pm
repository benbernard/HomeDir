package Amling::GRD::Command::Save;

use strict;
use warnings;

use Amling::GRD::Command;
use Amling::GRD::Command::Simple;
use Amling::GRD::Utils;

use base 'Amling::GRD::Command::Simple';

sub name
{
    return "save";
}

sub args
{
    return 1;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;
    my $tag = shift;

    $ctx->get('tags', {})->{$tag} = Amling::GRD::Utils::convert_commitlike('HEAD');
}

Amling::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
