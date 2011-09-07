package Amling::GRD::Command::Fixup;

use strict;
use warnings;

use Amling::GRD::Command::FSplatter;
use Amling::GRD::Command::Pick;
use Amling::GRD::Command::Simple;
use Amling::GRD::Command;
use Amling::GRD::Utils;

use base 'Amling::GRD::Command::Simple';

sub extended_handler
{
    my $s = shift;

    my ($commit, $msg);
    if($s =~ /^fixup ([^ ]+) ([^ ].*)$/)
    {
        $commit = $1;
        $msg = $2;
    }
    else
    {
        return undef;
    }

    return __PACKAGE__->new($commit, Amling::GRD::Utils::unescape_msg($msg));
}

sub name
{
    return "fixup";
}

sub args
{
    return 1;
}

sub execute_simple
{
    my $self = shift;
    my $ctx = shift;
    my $commit = shift;
    my $msg = shift;

    # push HEAD^
    push @{$ctx->get('commit-stack', [])}, Amling::GRD::Utils::convert_commitlike('HEAD^');

    # pick *
    my $pick_delegate;
    if(defined($msg))
    {
        $pick_delegate = Amling::GRD::Command::Pick->new($commit, $msg);
    }
    else
    {
        $pick_delegate = Amling::GRD::Command::Pick->new($commit);
    }
    $pick_delegate->execute($ctx);

    # fsplatter
    my $fsplatter_delegate = Amling::GRD::Command::FSplatter->new();
    $fsplatter_delegate->execute($ctx);
}

sub str_simple
{
    my $self = shift;
    my $commit = shift;
    my $msg = shift;

    return "fixup $commit" . (defined($msg) ? " (amended message)" : "");
}

Amling::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });
Amling::GRD::Command::add_command(\&extended_handler);

1;
