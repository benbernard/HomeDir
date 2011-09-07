package Amling::GRD::Command::Simple;

use strict;
use warnings;

use Amling::GRD::Command;
use Amling::GRD::Command::Simple;
use Amling::GRD::Utils;

sub handler
{
    my $class = shift;
    my $s = shift;

    my @s = split(/ /, $s);

    if(defined($class->min_args()) && @s < 1 + $class->min_args())
    {
        return undef;
    }

    if(defined($class->max_args()) && @s > 1 + $class->max_args())
    {
        return undef;
    }

    my $s0 = shift @s;
    if($s0 ne $class->name())
    {
        return undef;
    }

    return $class->new(@s);
}

sub new
{
    my $class = shift;

    my $self =
    {
        'args' => \@_,
    };

    bless $self, $class;

    return $self;
}

sub execute
{
    my $self = shift;
    my $ctx = shift;

    $self->execute_simple($ctx, @{$self->{'args'}});
}

sub str
{
    my $self = shift;

    return $self->str_simple(@{$self->{'args'}});
}

sub str_simple
{
    my $self = shift;

    return join(" ", $self->name(), @_);
}

sub min_args
{
    my $class = shift;

    return $class->args();
}

sub max_args
{
    my $class = shift;

    return $class->args();
}

1;
