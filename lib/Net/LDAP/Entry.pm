# Copyright (c) 1997-2000 Graham Barr <gbarr@pobox.com>. All rights reserved.
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

package Net::LDAP::Entry;

use strict;
use Net::LDAP::ASN qw(LDAPEntry);

sub new {
  my $self = shift;
  my $type = ref($self) || $self;

  my $entry = bless { 'changetype' => 'add' }, $type;

  $entry;
}

# Build attrs cache, created when needed

sub _build_attrs {
  my $self = shift;
  $self->{attrs} = { map { (lc($_->{type}),$_->{vals}) }  @{$self->{asn}{attributes}} };
}

# If we are passed an ASN structure we really do nothing

sub decode {
  my $self = shift;
  my $result = ref($_[0]) ? shift : $LDAPEntry->decode(shift)
    or return;

  %{$self} = ( asn => $result, changetype => 'modify');

  $self;
}


sub asn {
  shift->{asn}
}


sub encode {
  $LDAPEntry->encode( shift->{asn} );
}


sub dn {
  my $self = shift;
  @_ ? ($self->{asn}{objectName} = shift) : $self->{asn}{objectName};
}


sub carp {
  require Carp;
  goto &Carp::carp;
}


sub attributes {
  my $self = shift;
  carp("attributes called with arguments") if @_;
  map { $_->{type} } @{$self->{asn}{attributes}};
}


sub get_attribute {
  carp("->get_attribute depricated, use ->get") if $^W;
  goto &get;
}


sub get {
  my $self = shift;
  my $type = lc(shift);

  my $attrs = $self->{attrs} || _build_attrs($self);

  return unless exists $attrs->{$type};

  wantarray
    ? @{$attrs->{$type}}
    : $attrs->{$type};
}


sub changetype {
  my $self = shift;
  return $self->{'changetype'} unless @_;
  $self->{'changes'} = [];
  $self->{'changetype'} = shift;
}


sub changes {
  @{shift->{'changes'}}
}


sub add {
  my $self  = shift;
  my $cmd   = $self->{'changetype'} eq 'modify' ? [] : undef;
  my $attrs = $self->{attrs} || _build_attrs($self);

  while (my($type,$val) = splice(@_,0,2)) {
    $type = lc $type;

    push @{$self->{asn}{attributes}}, { type => $type, vals => ($attrs->{$type}=[])}
      unless exists $attrs->{$type};

    push @{$attrs->{$type}}, ref($val) ? @$val : $val;

    push @$cmd, $type, [ ref($val) ? @$val : $val ]
      if $cmd;

  }

  push(@{$self->{'changes'}}, 'add', $cmd) if $cmd;
}


sub replace {
  my $self  = shift;
  my $cmd   = $self->{'changetype'} eq 'modify' ? [] : undef;
  my $attrs = $self->{attrs} || _build_attrs($self);

  while(my($type, $val) = splice(@_,0,2)) {
    $type = lc $type;

    if (defined($val) and (!ref($val) or @$val)) {

      push @{$self->{asn}{attributes}}, { type => $type, vals => ($attrs->{$type}=[])}
	unless exists $attrs->{$type};

      @{$attrs->{$type}} = ref($val) ? @$val : ($val);

      push @$cmd, $type, [ ref($val) ? @$val : $val ]
	if $cmd;

    }
    else {
      delete $attrs->{$type};

      @{$self->{asn}{attributes}}
	= grep { $type ne lc($_->{type}) } @{$self->{asn}{attributes}};

      push @$cmd, $type, []
	if $cmd;

    }
  }

  push(@{$self->{'changes'}}, 'replace', $cmd) if $cmd;
}


sub delete {
  my $self = shift;

  unless (@_) {
    $self->changetype('delete');
    return;
  }

  my $cmd = $self->{'changetype'} eq 'modify' ? [] : undef;
  my $attrs = $self->{attrs} || _build_attrs($self);

  while(my($type,$val) = splice(@_,0,2)) {
    $type = lc $type;

    if (defined($val) and (!ref($val) or @$val)) {
      my %values;
      @values{@$val} = ();

      @{$attrs->{$type}}
        = grep { !exists $values{$_} } @{$attrs->{$type}};

      push @$cmd, $type, [ ref($val) ? @$val : $val ]
	if $cmd;
    }
    else {
      delete $attrs->{$type};

      @{$self->{asn}{attributes}}
	= grep { $type ne lc($_->{type}) } @{$self->{asn}{attributes}};

      push @$cmd, $type, [] if $cmd;
    }
  }

  push(@{$self->{'changes'}}, 'delete', $cmd) if $cmd;
}


sub update {
  my $self = shift;
  my $ldap = shift;
  my $mesg;
  my $cb = sub { $self->changetype('modify') unless $_[0]->code };

  if ($self->{'changetype'} eq 'add') {
    $mesg = $ldap->add($self, 'callback' => $cb);
  }
  elsif ($self->{'changetype'} eq 'delete') {
    $mesg = $ldap->delete($self, 'callback' => $cb);
  }
  else {
    $mesg = $ldap->modify($self, 'changes' => $self->{'changes'}, 'callback' => $cb);
  }

  return $mesg;
}


# Just for debugging

sub dump {
  my $self = shift;

  my $asn = $self->{asn};
  print "-" x 72,"\n";
  print "dn:",$asn->{objectName},"\n\n";

  my($attr,$val);
  my $l = 0;

  for (keys %{ $self->{attrs} || _build_attrs($self) }) {
    $l = length if length > $l;
  }

  my $spc = "\n  " . " " x $l;

  foreach $attr (@{$asn->{attributes}}) {
    $val = $attr->{vals};
    printf "%${l}s: ", $attr->{type};
    my($i,$v);
    $i = 0;
    foreach $v (@$val) {
      print $spc if $i++;
      print $v;
    }
    print "\n";
  }
}

1;