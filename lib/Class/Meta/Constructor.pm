package Class::Meta::Constructor;

# $Id: Constructor.pm,v 1.24 2004/01/09 01:14:46 david Exp $

use strict;

=head1 NAME

Class::Meta::Constructor - Class::Meta class constructor introspection

=head1 SYNOPSIS

  # Assuming MyApp::Thingy was generated by Class::Meta.
  my $class = MyApp::Thingy->class;

  print "\nConstructors:\n";
  for my $ctor ($class->constructors) {
      print "  o ", $ctor->name, $/;
      my $thingy = $ctor->call;
  }

=head1 DESCRIPTION

This class provides an interface to the C<Class::Meta> objects that describe
class constructors. It supports a simple description of the constructor, a
label, and the constructor visibility (private, protected, or public).

Class::Meta::Constructor objects are created by Class::Meta; they are never
instantiated directly in client code. To access the constructor objects for a
Class::Meta-generated class, simply call its C<class> method to retreive its
Class::Meta::Class object, and then call the C<constructors()> method on the
Class::Meta::Class object.

=cut

##############################################################################
# Dependencies                                                               #
##############################################################################
use strict;

##############################################################################
# Package Globals                                                            #
##############################################################################
our $VERSION = "0.01";

##############################################################################
# Private Package Globals
##############################################################################
my $croak = sub {
    require Carp;
    our @CARP_NOT = qw(Class::Meta);
    Carp::croak(@_);
};

##############################################################################
# Constructors                                                               #
##############################################################################
# We don't document new(), since it's a protected method, really. Its
# parameters are documented in Class::Meta.

sub new {
    my $pkg = shift;
    my $spec = shift;

    # Check to make sure that only Class::Meta or a subclass is constructing a
    # Class::Meta::Constructor object.
    my $caller = caller;
    $croak->("Package '$caller' cannot create " . __PACKAGE__ . " objects")
      unless UNIVERSAL::isa($caller, 'Class::Meta');

    # Make sure we can get all the arguments.
    $croak->("Odd number of parameters in call to new() when named "
             . "parameters were expected" ) if @_ % 2;
    my %p = @_;

    # Validate the name.
    $croak->("Parameter 'name' is required in call to new()")
      unless $p{name};
    $croak->("Constructor '$p{name}' is not a valid constructor name "
             . "-- only alphanumeric and '_' characters allowed")
      if $p{name} =~ /\W/;

    # Make sure the name hasn't already been used for another constructor or
    # method.
    $croak->("Method '$p{name}' already exists in class '$spec->{package}'")
      if exists $spec->{ctors}{$p{name}}
      or exists $spec->{meths}{$p{name}};

    # Check the visibility.
    if (exists $p{view}) {
        $croak->("Not a valid view parameter: '$p{view}'")
          unless $p{view} == Class::Meta::PUBLIC
          ||     $p{view} == Class::Meta::PROTECTED
          ||     $p{view} == Class::Meta::PRIVATE;
    } else {
        # Make it public by default.
        $p{view} = Class::Meta::PUBLIC;
    }

    # Validate or create the method caller if necessary.
    if ($p{caller}) {
        my $ref = ref $p{caller};
        $croak->("Parameter caller must be a code reference")
          unless $ref && $ref eq 'CODE'
      } else {
          $p{caller} = eval "sub { shift->$p{name}(\@_) }"
            if $p{view} > Class::Meta::PRIVATE;
      }

    # Create and cache the constructor object.
    $p{package} = $spec->{package};
    $spec->{ctors}{$p{name}} = bless \%p, ref $pkg || $pkg;

    # Index its view.
    if ($p{view} > Class::Meta::PRIVATE) {
        push @{$spec->{prot_ctor_ord}}, $p{name};
        push @{$spec->{ctor_ord}}, $p{name}
          if $p{view} == Class::Meta::PUBLIC;
    }

    # Let 'em have it.
    return $spec->{ctors}{$p{name}};
}


##############################################################################
# Instance Methods                                                           #
##############################################################################

=head1 INTERFACE

=head2 Instance Methods

=head3 name

  my $name = $ctor->name;

Returns the constructor name.

=head3 package

  my $package = $ctor->package;

Returns the package name of the class that constructor is associated with.

=head3 desc

  my $desc = $ctor->desc;

Returns the description of the constructor.

=head3 label

  my $desc = $ctor->label;

Returns label for the constructor.

=head3 view

  my $view = $ctor->view;

Returns the view of the constructor, reflecting its visibility. The possible
values are defined by the following constants:

=over 4

=item Class::Meta::PUBLIC

=item Class::Meta::PRIVATE

=item Class::Meta::PROTECTED

=back

=cut

sub name    { $_[0]->{name}    }
sub package { $_[0]->{package} }
sub desc    { $_[0]->{desc}    }
sub label   { $_[0]->{label}   }
sub view    { $_[0]->{view}    }

=head3 call

  my $obj = $ctor->call(@params);

Executes the constructor for the class, passing the parameters to it.

=cut

sub call {
    my $self = shift;
    my $code = $self->{caller}
      or $croak->("Cannot call constructor '", $self->name, "'");
    $code->($self->{package}, @_);
}

##############################################################################
# Private Methods
##############################################################################

sub build {
    my ($self, $specs) = @_;

    # Check to make sure that only Class::Meta or a subclass is building
    # constructors.
    my $caller = caller;
    $croak->("Package '$caller' cannot call " . __PACKAGE__ . "->build")
      unless UNIVERSAL::isa($caller, 'Class::Meta');

    # Build a construtor that takes a parameter list and assigns the
    # the values to the appropriate attributes.
    no strict 'refs';
    *{"$self->{package}::" . $self->name } = sub {
        my $class = ref $_[0] ? ref shift : shift;
        my $spec = $specs->{$class};

        # Just grab the parameters and let an error be thrown by Perl
        # if there aren't the right number of them.
        my %p = @_;
        my $new = bless {}, ref $class || $class;

        # Assign all of the attribute values.
        if ($spec->{attrs}) {
            foreach my $attr (values %{ $spec->{attrs} }) {
                my $key = $attr->name;
                if ($attr->authz >= Class::Meta::SET) {
                    # Let them set the value.
                    $attr->call_set($new, exists $p{$key}
                                      ? delete $p{$key}
                                      : $attr->default);
                } else {
                    # Use the default value.
                    $new->{$key} = $attr->default;
                }
            }
        }

        # Check for parameters for which attributes that don't exist.
        if (my @attributes = keys %p) {
            # Attempts to assign to non-existent attributes fail.
            my $c = $#attributes > 0 ? 'attributes' : 'attribute';
            local $" = "', '";
            $croak->("No such $c '@attributes' in $self->{package} objects");
        }
        return $new;
    };
}

1;
__END__

=head1 AUTHOR

David Wheeler <david@kineticode.com>

=head1 SEE ALSO

Other classes of interest within the Class::Meta distribution include:

=over 4

=item L<Class::Meta|Class::Meta>

=item L<Class::Meta::Class|Class::Meta::Class>

=item L<Class::Meta::Method|Class::Meta::Method>

=item L<Class::Meta::Attribute|Class::Meta::Attribute>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2004, David Wheeler. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut


1;
__END__
