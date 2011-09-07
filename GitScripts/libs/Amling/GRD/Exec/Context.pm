package Amling::GRD::Exec::Context;

use strict;
use warnings;

sub new
{
    my $class = shift;

    my $self =
    {
    };

    bless $self, $class;

    return $self;
}

sub get
{
    my $self = shift;
    my $item = shift;
    my $def = shift;

    if(defined($def) && !defined($self->{$item}))
    {
        $self->{$item} = $def;
    }

    return $self->{$item};
}

sub set
{
    my $self = shift;
    my $item = shift;
    my $def = shift;

    $self->{$item} = $def;
}

1;
