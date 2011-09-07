package BiffBuff::Config;

use strict;
use warnings;

use Data::Dumper;
use IO::Handle;
use Term::ReadKey;

use HumanStorable qw(store_file read_file);

# Must reap zombies... This could interfere with other people in the program,
# but screw 'em
sub REAPER {
  my $waitedpid = wait;
}
$SIG{CHLD} = \&REAPER;

sub new {
  my $class = shift;
  my $this = {};

  bless $this, $class;
  $this->_init();
  return $this;
}

sub _init {
  my $this = shift;
  my $file = get_rc_file();

  my $config = read_file($file);
  $this->{'CONFIG'} = $config;

  $this->_init_commands();

  foreach my $command ( @{$this->get_commands()} ) {
    if ( $command->needs_password() ) {
      $this->initialize_password();
    }
  }

  $this->run_programs();
}

sub _init_commands {
  my $this = shift;

  my @commands;
  foreach my $command_hash (values %{$this->{'CONFIG'}->{'commands'}} ) {
    push @commands, Command->new($command_hash);
  }

  $this->{'COMMANDS'} = \@commands;
}

sub run_programs {
  my $this = shift;

  my $now = time();
  foreach my $command ( @{$this->get_commands()} ) {
    $command->run_if_past_interval($this->get_password());
  }
};

sub initialize_password {
  my $this = shift;
  return $this->{'PASSWORD'} if ( $this->{'PASSWORD'} );

  my $password = $this->prompt_for_password();
  return $this->{'PASSWORD'} = $password;
}

sub get_password {
  my $this = shift;
  return $this->{'PASSWORD'};
}

sub prompt_for_password {
  STDOUT->autoflush(1);

  print "Password: ";
  ReadMode('noecho');
  my $password = ReadLine(0);
  ReadMode(0);

  print "\n";

  chomp $password;
  return sub { return $password };
}

sub get_commands {
  my $this = shift;
  return $this->{'COMMANDS'};
}

sub _get_home {
  my $uid = (getpwuid($<))[0];
  return "/home/$uid";
}

sub get_rc_file {
  return $ENV{'BIFFBUFF_RC'} || _get_home() . '/.biffbuffrc';
}

package Command;

use strict;
use warnings;

use IPC::Open3;

sub new {
  my $class  = shift;
  my $config = shift;
  my $this = { %$config };
  bless $this, $class;
  return $this;
}

sub set_pid {
  my $this = shift;
  return $this->{'PID'} = shift;
}

sub get_pid {
  my $this = shift;
  return $this->{'PID'};
}

sub is_running {
  my $this = shift;
  my $pid = $this->get_pid();
  return 0 unless ( $pid );

  my $results = kill 0, $pid;
  return $results == 1;
}

sub last_run {
  my $this = shift;
  return $this->{'LAST_RUN'} || 0;
}

sub set_last_run {
  my $this = shift;
  return $this->{'LAST_RUN'} = shift;
}

sub run_if_past_interval {
  my $this     = shift;
  my $password = shift;

  return if ( $this->is_running() );

  my $time     = time();
  my $last_run = $this->last_run();
  my $interval = $this->interval();

  if ( ($time - $last_run) > $interval )  {
    my $pid = $this->run($password);
    $this->set_pid($pid);
    $this->set_last_run(time());
  }
}

sub run {
  my $this     = shift;
  my $password = shift;

  my $program = $this->{'program'};

  my ($child_out, $child_in, $child_err);
  my $pid = open3($child_in, $child_out, $child_err, $program);
  print $child_in $password->() . "\n" if ( $this->needs_password() );
  close $child_in;

  # if we close the child out, it'll die before its time... I think, so prevent
  # GC
  $this->{'CHILD_OUT'} = $child_out;
  $this->{'CHILD_ERR'} = $child_err;

  return $pid;
}

sub interval {
  my $this = shift;
  return $this->{'interval_seconds'};
}

sub needs_password {
  my $this = shift;
  return $this->{'needs_password'};
}

1;
