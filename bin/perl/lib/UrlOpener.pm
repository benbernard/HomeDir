package UrlOpener;

use strict;
use warnings;

use IPC::Open3;
use POSIX qw(:sys_wait_h);

sub open_url {
  my $url             = shift;
  my $suppress_output = shift;

  my $opener = UrlOpener->new(@_);
  $opener->run_command_for_url($url, $suppress_output);
}

sub get_usage {
  return <<USAGE;
UrlOpener:
  The url opener can be controlled by the ~/.urlview file.  You can change this
  file by setting the environment variable URLOPENER_RC to a different file.

  This file may contain anything, but should have a COMMAND line with a \%s for
  where the url should end up.  This is the command to performs whatever url
  action you wish, for instance:

  COMMAND /usr/bin/firefox \%s &

  If you set the env variable URLOPENER_LOG_FILE, then every url opened will be
  logged there with a timestamp notation

USAGE
}

sub print_usage {
  return get_usage();
}

sub new {
  my $class   = shift;
  my %args    = @_;

  my $this = {
    RC_FILE  => $args{rc_file} || $ENV{'URLOPENER_RC'} || $ENV{'HOME'} . '/.urlview',
    LOG_FILE => $args{log_file} || $ENV{'URLOPENER_LOG_FILE'},
  };

  bless $this, $class;
  $this->_parse_rc_file();
  return $this;
}

sub _parse_rc_file {
  my $this = shift;
  my $file = $this->get_rc_file();

  open ( my $fh, '<', $file ) or die "Could not open url rc file: $file: $!";

  my $command;

  while ( my $line = <$fh> ) {
    chomp $line;

    if ( $line =~ m/^\s*COMMAND (.*)$/ ) {
      $command = $1;
      last;
    }
  }

  close $fh;

  $this->{'COMMAND'} = $command;
}

sub get_rc_file {
  my $this = shift;
  return $this->{'RC_FILE'};
}

sub get_command {
  my $this = shift;
  return $this->{'COMMAND'};
}

sub command_for_url {
  my $this = shift;
  my $url = shift;

  my $command = $this->get_command();

  $command =~ s/['"]\%s['"]/\%s/;
  $command =~ s/\%s/'$url'/;

  return $command;
}

sub run_command_for_url {
  my $this            = shift;
  my $url             = shift;
  my $suppress_output = shift;

  my $command = $this->command_for_url($url);
  $this->log_url($url);

  if ( ! $suppress_output ) {
    system($command);
  }
  else {
    my ($in, $out, $err);
    my $pid = open3($in, $out, $err, $command) or die "could not fork $command: $!";
    close $in;

    while(<$out>) {}

    waitpid $pid, &WNOHANG;
  }
}

sub log_url {
  my $this = shift;
  my $url  = shift;
  my $file = $this->get_log_file();

  return unless ( $file );

  open ( my $fh, '>>', $file ) or die "Could not open log file $file: $!";
  print $fh localtime() . ": $url\n";
  close $fh;
}

sub get_log_file {
  my $this = shift;
  return $this->{'LOG_FILE'};
}

1;
