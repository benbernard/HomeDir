package Amling::Git::GRD::Command::DetachedHead;

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
    return 0;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;

    $ctx->set('head', [0, Amling::Git::Utils::convert_commitlike("HEAD")]);
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
