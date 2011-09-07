package BiffBuff::Queue;

use strict;
use warnings;

use BiffBuff::Item;

use File::Path qw(mkpath);
use File::Basename qw(dirname);
use JSON::Syck;

sub new {
  my $class   = shift;
  my %args    = @_;

  my $this = {
    VERBOSE => $args{'verbose'},
    ITEMS   => [],
  };

  bless $this, $class;
  $this->_init($args{'skip_load'});
  return $this;
}

sub _init {
  my $this      = shift;
  my $skip_load = shift;
  my $dir  = $this->get_queue_dir();
  mkpath($dir);

  $this->reload_items() unless ( $skip_load );
  $this->load_ids();
}

sub load_ids {
  my $this = shift;
  my $file = $this->get_ids_file();

  return unless ( -e $file );

  my $contents = slurp($file);
  return unless ( $contents );

  my $data = JSON::Syck::Load($contents);

  $this->{'IDS'} = $data;

  my @to_remove;

  foreach my $id ( keys %{$this->{'IDS'}} ) {
    my $time = $this->{'IDS'}->{$id};
    if ( $time < time() ) {
      push @to_remove, $id;
    }
  }

  return unless ( scalar @to_remove );

  foreach my $removed_id (@to_remove) {
    delete $this->{'IDS'}->{$removed_id};
  }

  $this->write_ids();
}

sub update_items {
  my $this = shift;

  my @items = @{$this->get_items()};
  foreach my $item (@items) {
    if ( $item->is_expired() ) {
      $this->remove_item($item);
    }
  }

  $this->load_ids();
}

sub reload_items {
  my $this = shift;
  my $changed;
  ($this->{'ITEMS'}, $changed) = $this->_read_items();
  return $changed;
}

sub _read_items {
  my $this = shift;

  my $files = $this->_get_files($this->get_queue_dir());
  my @objects;

  my @changed_objects;

  foreach my $file (@$files) {
    my $item = $this->get_or_create_item($file);
    next unless ( $item );

    my $reloaded = $item->reload();
    push @objects, $item;

    if ( $reloaded ) {
      push @changed_objects, $item;
    }
  }

  return (\@objects, \@changed_objects);
}

sub get_or_create_item {
  my $this = shift;
  my $file = shift;

  foreach my $item (@{$this->get_items()}) {
    return $item if ( $item->get_file() eq $file );
  }

  my $item_to_return;
  eval {
    $item_to_return = BiffBuff::Item->new(file => $file);
  };
  if ( $@ ) {
    undef $@; # ignore it!
    return;
  }

  return $item_to_return;
}

sub get_items {
  my $this = shift;
  return $this->{'ITEMS'};
}

sub get_item {
  my $this  = shift;
  my $index = shift;

  return (@{$this->{'ITEMS'}})[$index];
}

sub _get_files {
  my $this = shift;
  my $dir  = shift;

  opendir(DIR, $dir) or die "Could not open $dir: $!";
  my @files = grep { -f "$dir/$_" } readdir(DIR);
  close DIR;

  return [ sort { (stat($a))[9] <=> (stat($b))[9] } (map { "$dir/$_" } @files) ];
}

sub get_queue_dir {
  my $this = shift;
  return $ENV{'BIFFBUFF_DIR'} || _get_home() . '/.biffbuff';
}

sub add_id {
  my $this = shift;
  my $id   = shift;

  return unless ( defined $id );

  $this->{'IDS'}->{$id} = time() + (5 * 60 * 60); # 5 hours in seconds
  $this->write_ids();
}

sub seen_id {
  my $this = shift;
  my $id   = shift;

  return 0 unless ( defined $id );
  return exists $this->{'IDS'}->{$id};
}

sub get_ids_file {
  my $this = shift;
  return $this->get_queue_dir() . '/data/ids';
}

sub write_ids {
  my $this = shift;

  my $dir      = $this->get_queue_dir();
  my $file     = $this->get_ids_file();
  my $data_dir = dirname($file);

  mkpath($data_dir) unless ( -e $data_dir );

  my $ids = $this->{'IDS'} || {};
  my $json = JSON::Syck::Dump($ids);

  open ( my $fh, '>', $file ) or die "Could not open for write $file: $!";
  print $fh $json;
  close $fh;

}

sub slurp {
  my $file = shift;
  local $/;

  open (my $fh, '<', $file) or die "Could not open $file:$!";
  my $contents = <$fh>;
  close $fh;

  return $contents;
}

sub add_item {
  my $this = shift;
  my $new_item = shift;

  # Dedup based on id
  return if ( $this->seen_id($new_item->get_raw_id()) );
  $this->add_id($new_item->get_raw_id());

  my $file = $this->_get_filename_for_item($new_item);
  $new_item->set_file($file);
  $new_item->write();
  push @{$this->{'ITEMS'}}, $new_item;

}

sub _get_filename_for_item {
  my $this = shift;
  my $item = shift;

  my $time = $item->get_time();
  $time =~ s/ /-/g;

  my $count = 0;
  while ( 1 ) {
    my $filename = $this->get_queue_dir() . "/$time.$count";
    return $filename unless ( -e $filename );
    $count++;
  }
}

sub _get_home {
  my $uid = (getpwuid($<))[0];
  return "/home/$uid";
}

sub clear_items {
  my $this = shift;

  foreach my $item (@{$this->get_items()}) {
    $item->delete_file();
  }

  $this->{'ITEMS'} = [];
}

sub remove_item {
  my $this = shift;
  my $item = shift;

  my $file = $item->get_file();

  $this->{'ITEMS'} = [ grep { $_->get_file() ne $file } @{$this->{'ITEMS'}} ];
  $item->delete_file();
}

1;
