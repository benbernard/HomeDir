#!/usr/bin/perl -w

use strict;

use lib 'Growl/Bindings/perl/Mac-Growl/lib';

use Mac::Growl;
use Getopt::Long;

my ($type, $from, $message);

GetOptions(
  'type=s'    => \$type,
  'from=s'    => \$from,
  'message=s' => \$message,
);

my $notes = {
  PRIVATE => {
    NAME        => "Private Message",
    TITLE       => "Private: %s",
    DESCRIPTION => "%s",
    STICKY      => 1,
  },
  PUBLIC => {
    NAME        => "Public Message",
    TITLE       => "%s",
    DESCRIPTION => "%s",
    STICKY      => 0,
  },
};

my $noteNames = [ map { $notes->{$_}->{NAME} } keys %$notes ];

Mac::Growl::RegisterNotifications('irssi', $noteNames, $noteNames, 'iTerm');

unless ( $type &&  $notes->{$type} ) {
  die "No valid type specified";
}

my $note = $notes->{$type};

my $title  = sprintf $note->{TITLE},       $from;
my $desc   = sprintf $note->{DESCRIPTION}, $message;
my $name   = $note->{NAME};
my $sticky = $note->{STICKY};

Mac::Growl::PostNotification('irssi', $name, $title, $desc, $sticky);
