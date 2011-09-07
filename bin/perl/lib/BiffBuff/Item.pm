package BiffBuff::Item;

use strict;
use warnings;

use POSIX qw(strftime);
use File::Path qw(mkpath);
use JSON::Syck;
use Date::Parse qw(str2time);

my $current_id  = 0;
my $TIME_FORMAT = '%Y-%m-%d %H:%M:%S';

my $DEFAULTS = {
  displayed   => 1,
  urgent      => 0,
  expire_in   => 10,
  'time'      => \&get_current_time,
  subject     => 'defualt subject',
  description => 'no description specified',
  program     => $0,
  url         => undef,
};

sub get_current_time {
  return strftime($TIME_FORMAT, localtime);
}

sub get_url {
  my $this = shift;
  return $this->{'url'};
}

sub set_url {
  my $this       = shift;
  $this->{'url'} = shift;
  $this->write();
}

sub get_time {
  my $this = shift;
  return $this->{'time'};
}

sub set_time {
  my $this        = shift;
  $this->{'time'} = shift;
  $this->write();
}

sub get_expire_in {
  my $this = shift;
  return $this->{'expire_in'};
}

sub set_expire_in {
  my $this             = shift;
  $this->{'expire_in'} = shift;
  $this->write();
}

sub new {
  my $class   = shift;
  my %args    = @_;

  my $this = {
    AUTO_ID   => $current_id++,
  };

  foreach my $key (keys %args) {
    $this->{$key} = $args{$key};
  }

  foreach my $default_key (keys %$DEFAULTS) {
    next if ( exists $this->{$default_key} );
    my $value = $DEFAULTS->{$default_key};
    if ( ref($value) eq 'CODE' ) {
      $this->{$default_key} = $value->();
    } 
    else {
      $this->{$default_key} = $value;
    }
  }

  bless $this, $class;

  $this->reload();
  return $this;
}

sub get_raw_id {
  my $this = shift;
  return $this->{'ID'};
}

sub get_id {
  my $this = shift;
  return $this->{'ID'} || $this->{'AUTO_ID'};
}

sub is_displayed {
  my $this = shift;
  return $this->{'displayed'};
}

sub set_displayed {
  my $this = shift;
  $this->{'displayed'} = shift;
  $this->write();
}

sub get_subject {
  my $this = shift;
  return $this->{'subject'};
}

sub set_subject {
  my $this = shift;
  $this->{'subject'} = shift;
  $this->write();
}

sub get_description {
  my $this = shift;
  return $this->{'description'};
}

sub set_description {
  my $this = shift;
  $this->{'description'} = shift;
  $this->write();
}

sub get_program {
  my $this = shift;
  return $this->{'program'};
}

sub set_program {
  my $this = shift;
  $this->{'program'} = shift;
  $this->write();
}

sub get_last_load {
  my $this = shift;
  return $this->{'last_load'};
}

sub set_last_load {
  my $this = shift;
  $this->{'last_load'} = shift;
}

sub reload {
  my $this = shift;

  my $file      = $this->get_file();

  return unless ($file);

  my $mtime     = (stat($file))[9];
  my $last_load = $this->get_last_load() || 0;

  return 0 if ( $mtime < $last_load );

  my $contents = slurp($file);
  my $data = JSON::Syck::Load($contents);

  die "Not a hash!" unless ( ref($data) && ref($data) eq 'HASH');

  foreach my $key (keys %$data) {
    my $value = $data->{$key};
    $this->{$key} = $value;
  }

  $this->set_last_load(time);

  return 1;
}

sub write_to_file {
  my $this = shift;
  my $file = shift;

  my %data = %$this;
  delete $data{'file'};
  delete $data{'AUTO_ID'};
  delete $data{'LAST_LOAD'};

  my $json = JSON::Syck::Dump(\%data);

  open ( my $fh, '>', $file ) or die "Could not open for write $file: $!";
  print $fh $json;
  close $fh;

  $this->set_last_load(time);
}

sub delete_file {
  my $this = shift;
  #warn "Unlinking: " . $this->get_file() . "\n";
  unlink $this->get_file();
}

sub get_field {
  my $this = shift;
  my $name = shift;
  return $this->{'data'}->{$name};
}

sub is_urgent {
  my $this = shift;
  return $this->{'urgent'};
}

sub set_urgent {
  my $this = shift;
  $this->{'urgent'} = shift;
  $this->write();
}

sub display_line {
  my $this     = shift;
  my $blink_on = shift;

  my $time    = $this->get_time() || '';
  my $subject = $this->get_subject() || '';
  my $program = $this->get_program() || '';

  my $line = "$time - $program - $subject";

  if ( $this->is_urgent() && $blink_on ) {
    return "<bold><reverse>$line<reverse></bold>";
  }

  return $line;
}

sub is_expired {
  my $this = shift;

  return 0 unless ( $this->get_expire_in() > 0 );

  my $creation = str2time($this->get_time());
  my $now      = time();

  return ($now - $creation) > $this->get_expire_in();
}

sub time_till_expiration {
  my $this = shift;
  return -1 unless ( $this->get_expire_in() > 0 );

  my $creation = str2time($this->get_time());
  my $now      = time();

  return ($creation + $this->get_expire_in()) - $now;
}

sub long_description {
  my $this = shift;

  my $time    = $this->get_time() || '';
  my $subject = $this->get_subject() || '';
  my $program = $this->get_program() || '';

  my $url_print = '';
  if ( my $url = $this->get_url() ) {
    $url_print = "Url     : $url\n";
  }

  my $description = $this->get_description() || '';

  return <<DESC;
Time    : $time
Program : $program
Subject : $subject
$url_print
$description
DESC
}

sub set_file {
  my $this = shift;
  my $file = shift;

  $this->{'file'} = $file;
}

sub get_file {
  my $this = shift;
  return $this->{'file'};
}

sub slurp {
  my $file = shift;
  local $/;

  open (my $fh, '<', $file) or die "Could not open $file:$!";
  my $contents = <$fh>;
  close $fh;

  return $contents;
}

sub write {
  my $this = shift;
  $this->write_to_file($this->get_file());
}

1;
