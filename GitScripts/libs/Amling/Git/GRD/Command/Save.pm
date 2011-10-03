package Amling::Git::GRD::Command::Save;

use strict;
use warnings;

use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Command;
use Amling::Git::Utils;

use base 'Amling::Git::GRD::Command::Simple';

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

    $ctx->get('tags', {})->{$tag} = Amling::Git::Utils::convert_commitlike('HEAD');
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
