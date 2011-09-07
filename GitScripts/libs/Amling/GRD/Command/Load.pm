package Amling::GRD::Command::Load;

use strict;
use warnings;

use Amling::GRD::Command;
use Amling::GRD::Command::Simple;
use Amling::GRD::Utils;

use base 'Amling::GRD::Command::Simple';

sub name
{
    return "load";
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

    my $commit = $ctx->get('tags', {})->{$tag} || die "Load of undefined tag $tag";
    Amling::GRD::Utils::run("git", "checkout", $commit) || die "Cannot checkout $commit";
}

Amling::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });

1;
