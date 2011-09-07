#!/usr/bin/perl -w

use strict;
use warnings;

use YAML::Syck;
use Data::Dumper;
use Date::Manip;
use Getopt::Long;
use IO::Handle;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use BiffBuff::Queue;
use BiffBuff::Item;

use POSIX qw(:sys_wait_h strftime);

my $GOOGLE_CLI = '/usr/bin/google';

my $TIME_FORMAT      = '%Y/%m/%d %H:%M:%S';
my $window_time_mins = 15;

my $expire;

my $current_time = time();

GetOptions(
  'expire!'       => \$expire,
  'window-mins=s' => \$window_time_mins,
  'time=s'        => \$current_time,
  'help'          => sub { print_usage() },
);

my $events = get_calender_events_after($current_time);

print Dumper $events;

my $later  = $current_time + ($window_time_mins * 60);

my $queue = BiffBuff::Queue->new();

foreach my $event (@$events) {
  next unless ( event_before($event, $later) );
  my $biff = get_biff_for_event($event, $expire);
  $queue->add_item($biff);
}

sub get_biff_for_event {
  my $event  = shift;
  my $expire = shift;

  my $expire_in = -1;
  if ( $expire ) {
    $expire_in = 15*60; # 15 mins
  }

  my $start = UnixDate(ParseDate('epoch ' . $event->{'start'}), $TIME_FORMAT);
  my $end   = UnixDate(ParseDate('epoch ' . $event->{'end'}), $TIME_FORMAT);

  my $description = <<DESC;
Start: $start
End:   $end
Where: $event->{where}

$event->{title}
DESC

  my $item = BiffBuff::Item->new(
    subject     => $event->{'title'},
    program     => 'calendar',
    expire_in   => $expire_in,
    urgent      => 1,
    description => $description,
    ID          => $event->{'id'},
    url         => $event->{'url'},
  );

  return $item;
}

sub get_calender_events_after {
  my $time     = shift;

  my @events;
  push @events, @{get_events_for_user('sample@example.com', $time)};

  return [ grep { event_after($_, $time) } @events ];
}

sub get_events_for_user {
  my $user = shift;
  my $time = shift;

  my $date = UnixDate(ParseDate("epoch $time"), '%Y-%m-%d');

  open(my $fh, '-|', $GOOGLE_CLI, 'calendar', '-u', $user, '--date', $date, '--fields', 'title,url,when,where', '--delimiter', chr(30), 'list') or die "Could not open google cli: $!";

  my $events    = [];
  my $in_events = 0;

  while ( my $line = <$fh> ) {
    chomp $line;
    if ( ! $in_events ) {
      if ( $line =~ m/\[$user\]/ ) {
        $in_events = 1;
      }
      next;
    }

    my ($title, $url, $when, $where) = split(chr(30), $line);

    my ($date_start, $date_end) = split(' - ', $when);

    my ($id) = $url =~ m/eid=([0-9A-Za-z]+)/;

    my $event = {
      title => $title,
      start => UnixDate(ParseDate($date_start), '%s'),
      end   => UnixDate(ParseDate($date_end), '%s'),
      id    => $id,
      where => $where,
      url   => $url,
    };

    push @$events, $event;
  }
  return $events;
}

sub event_after {
  my $event = shift;
  my $time  = shift;

  return $event->{'start'} > $time;
}

sub event_before {
  my $event      = shift;
  my $time       = shift;

  return $time > $event->{'start'};
}

sub get_password {
  STDOUT->autoflush(1);

  print "Password: ";
  ReadMode('noecho');
  my $password = ReadLine(0);
  ReadMode(0);

  print "\n";

  chomp $password;
  return sub { return $password };
}

sub print_usage {
  print <<USAGE;
$0
  Biffs for events on the calendar.  See the BiffBuff script for a front end
  for these biffs.  And the assocated wiki node.

  --(no)expire  - Defaults to --expire, if --noexpire is set, biffs will not
                  automaticaly expire
  --window-mins - Defaults to 15, mins from now to biff for

  Examples:
    $0
    $0 --window-mins 30 --noexpire
USAGE

  exit 1;
}

# We make our own specialization of LWP::UserAgent that asks for
# user/password if document is protected.
package StoredCredentialsAgent;

use base 'LWP::UserAgent';

sub new { 
  my $self = LWP::UserAgent::new(@_);
  $self->agent("lwp-request/CalBiff");
  $self;
}

sub set_credentials {
  my $this             = shift;
  my $user             = shift;
  my $password_closure = shift;

  $this->{'SCA_USER'} = $user;
  $this->{'SCA_PASSWORD_CLOSURE'} = $password_closure;
}

sub get_basic_credentials {
  my($this, $realm, $uri) = @_;

  my @return = ($this->{'SCA_USER'}, $this->{'SCA_PASSWORD_CLOSURE'}->());
  return @return;
}

# This is so dumb.  We have to remove the Negotiate header from the server
# response, otherwise LWP is going to try to use kerberos, which exchange can't
# auth with.  So, we need to remove it.
sub simple_request {
  my $this = shift;
  my $response = $this->SUPER::simple_request(@_);

  my $www_athen_headers = $response->{'_headers'}->{'www-authenticate'};
  @$www_athen_headers = grep { $_ ne 'Negotiate' } @$www_athen_headers;

  return $response;
}


