package Amling::Git::GRD::Command::Fixup;

use strict;
use warnings;

use Amling::Git::GRD::Command::FSplatter;
use Amling::Git::GRD::Command::Pick;
use Amling::Git::GRD::Command::Simple;
use Amling::Git::GRD::Command;
use Amling::Git::GRD::Utils;
use Amling::Git::Utils;

use base 'Amling::Git::GRD::Command::Simple';

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

    return __PACKAGE__->new($commit, Amling::Git::GRD::Utils::unescape_msg($msg));
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
    push @{$ctx->get('commit-stack', [])}, Amling::Git::Utils::convert_commitlike('HEAD^');

    # pick *
    my $pick_delegate;
    if(defined($msg))
    {
        $pick_delegate = Amling::Git::GRD::Command::Pick->new($commit, $msg);
    }
    else
    {
        $pick_delegate = Amling::Git::GRD::Command::Pick->new($commit);
    }
    $pick_delegate->execute($ctx);

    # fsplatter
    my $fsplatter_delegate = Amling::Git::GRD::Command::FSplatter->new();
    $fsplatter_delegate->execute($ctx);
}

sub str_simple
{
    my $self = shift;
    my $commit = shift;
    my $msg = shift;

    return "fixup $commit" . (defined($msg) ? " (amended message)" : "");
}

Amling::Git::GRD::Command::add_command(sub { return __PACKAGE__->handler(@_) });
Amling::Git::GRD::Command::add_command(\&extended_handler);

1;
