package Class::Meta::Attribute;

# $Id: Attribute.pm,v 1.34 2004/01/20 21:34:48 david Exp $

=head1 NAME

Class::Meta::Attribute - Class::Meta class attribute introspection

=head1 SYNOPSIS

  # Assuming MyApp::Thingy was generated by Class::Meta.
  my $class = MyApp::Thingy->class;
  my $thingy = MyApp::Thingy->new;

  print "\nAttributes:\n";
  for my $attr ($class->attributes) {
      print "  o ", $attr->name, " => ", $attr->call_get($thingy), $/;
      if ($attr->authz >= Class::Meta::SET && $attr->type eq 'string') {
          $attr->call_get($thingy, 'hey there!');
          print "    Changed to: ", $attr->call_get($thingy) $/;
      }
  }

=head1 DESCRIPTION

An object of this class describes an attribute of a class created by
Class::Meta. It includes metadata such as the name of the attribute, its data
type, its accessibility, and whether or not a value is required. It also
provides methods to easily get and set the value of the attribute for a given
instance of the class.

Class::Meta::Attribute objects are created by Class::Meta; they are never
instantiated directly in client code. To access the attribute objects for a
Class::Meta-generated class, simply call its C<class> method to retrieve
its Class::Meta::Class object, and then call the C<attributes()> method on
the Class::Meta::Class object.

=cut

##############################################################################
# Dependencies                                                               #
##############################################################################
use strict;

##############################################################################
# Package Globals                                                            #
##############################################################################
our $VERSION = "0.13";

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
    # Class::Meta::Attribute object.
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
    # Is this too paranoid?
    $croak->("Attribute '$p{name}' is not a valid attribute name "
             . "-- only alphanumeric and '_' characters allowed")
      if $p{name} =~ /\W/;

    # Grab the package name.
    $p{package} = $spec->{package};

    # Set the required attribute.
    $p{required} = exists $p{required} ? $p{required} ? 1 : 0 : 0;

    # Make sure the name hasn't already been used for another attribute
    $croak->("Attribute '$p{name}' already exists in class",
             " '", $spec->{attrs}{$p{name}}{package}, "'")
      if exists $spec->{attrs}{$p{name}};

    # Check the view.
    if (exists $p{view}) {
        $croak->("Not a valid view parameter: '$p{view}'")
          unless $p{view} == Class::Meta::PUBLIC
          or     $p{view} == Class::Meta::PROTECTED
          or     $p{view} == Class::Meta::PRIVATE;
    } else {
        # Make it public by default.
        $p{view} = Class::Meta::PUBLIC;
    }

    # Check the authorization level.
    if (exists $p{authz}) {
        $croak->("Not a valid authz parameter: '$p{authz}'")
          unless $p{authz} == Class::Meta::NONE
          or     $p{authz} == Class::Meta::READ
          or     $p{authz} == Class::Meta::WRITE
          or     $p{authz} == Class::Meta::RDWR;
    } else {
        # Make it read/write by default.
        $p{authz} = Class::Meta::RDWR;
    }

    # Check the creation constant.
    if (exists $p{create}) {
        $croak->("Not a valid create parameter: '$p{create}'")
          unless $p{create} == Class::Meta::NONE
          or     $p{create} == Class::Meta::GET
          or     $p{create} == Class::Meta::SET
          or     $p{create} == Class::Meta::GETSET;
    } else {
        # Relyl on the authz setting by default.
        $p{create} = $p{authz};
    }

    # Check the context.
    if (exists $p{context}) {
        $croak->("Not a valid context parameter: '$p{context}'")
          unless $p{context} == Class::Meta::OBJECT
          or     $p{context} == Class::Meta::CLASS;
    } else {
        # Put it in object context by default.
        $p{context} = Class::Meta::OBJECT;
    }

    # Check the default.
    if (exists $p{default}) {
        # A code ref should be executed when the default is called.
        $p{_def_code} = delete $p{default}
          if ref $p{default} eq 'CODE';
    }

    # Create and cache the attribute object.
    $spec->{attrs}{$p{name}} = bless \%p, ref $pkg || $pkg;

    # Index its view.
    if ($p{view} > Class::Meta::PRIVATE) {
        push @{$spec->{prot_attr_ord}}, $p{name};
        push @{$spec->{attr_ord}}, $p{name}
          if $p{view} == Class::Meta::PUBLIC;
    }

    # Let 'em have it.
    return $spec->{attrs}{$p{name}};
}

##############################################################################
# Instance Methods                                                           #
##############################################################################

=head1 INTERFACE

=head2 Instance Methods

=head3 name

  my $name = $attr->name;

Returns the name of the attribute.

=head3 type

  my $type = $attr->type;

Returns the name of the attribute's data type. Typical values are "scalar",
"string", and "boolean". See L<Class::Meta|Class::Meta/"Data Types"> for a
complete list.

=head3 desc

  my $desc = $attr->desc;

Returns a description of the attribute.

=head3 label

  my $label = $attr->label;

Returns a label for the attribute, suitable for use in a user interface. It is
distinguished from the attribute name, which functions to name the accessor
methods for the attribute.

=head3 package

  my $package = $attr->package;

Returns the package name of the class that attribute is associated with.

=head3 view

  my $view = $attr->view;

Returns the view of the attribute, reflecting its visibility. The possible
values are defined by the following constants:

=over 4

=item Class::Meta::PUBLIC

=item Class::Meta::PRIVATE

=item Class::Meta::PROTECTED

=back

=head3 context

  my $context = $attr->context;

Returns the context of the attribute, essentially whether it is a class or
object attribute. The possible values are defined by the following constants:

=over 4

=item Class::Meta::CLASS

=item Class::Meta::OBJECT

=back

=head3 authz

  my $authz = $attr->authz;

Returns the authorization for the attribute, which determines whether it can be
read or changed. The possible values are defined by the following constants:

=over 4

=item Class::Meta::READ

=item Class::Meta::WRITE

=item Class::Meta::RDWR

=item Class::Meta::NONE

=back

=cut

sub name     { $_[0]->{name}     }
sub type     { $_[0]->{type}     }
sub desc     { $_[0]->{desc}     }
sub label    { $_[0]->{label}    }
sub required { $_[0]->{required} }
sub package  { $_[0]->{package}  }
sub view     { $_[0]->{view}     }
sub context  { $_[0]->{context}  }
sub authz    { $_[0]->{authz}    }

##############################################################################

=head3 default

  my $default = $attr->default;

Returns the default value for a new instance of this attribute. Since the
default value can be determined dynamically, the value returned by
C<default()> may change on subsequent calls. It all depends on what was
passed for the C<default> parameter in the call to C<add_attribute()> on the
Class::Meta object that generated the class.

=cut

sub default {
    if (my $code = $_[0]->{_def_code}) {
        return $code->();
    }
    return $_[0]->{default};
}

##############################################################################

=head3 call_get

  my $value = $attr->call_get($thingy);

This method calls the "get" accessor method on the object passed as the sole
argument and returns the value of the attribute for that object. Note that it
uses a C<goto> to execute the accessor, so the call to C<call_set()> itself
will not appear in a call stack trace.

=cut

sub call_get   {
    my $self = shift;
    my $code = $self->{_get}
      or $croak->("Cannot get attribute '", $self->name, "'");
    goto &$code;
}

##############################################################################

=head3 call_set

  $attr->call_set($thingy, $new_value);

This method calls the "set" accessor method on the object passed as the first
argument and passes any remaining arguments to assign a new value to the
attribute for that object. Note that it uses a C<goto> to execute the
accessor, so the call to C<call_set()> itself will not appear in a call stack
trace.

=cut

sub call_set   {
    my $self = shift;
    my $code = $self->{_set}
      or $croak->("Cannot set attribute '", $self->name, "'");
    goto &$code;
}

##############################################################################
# Private Methods
##############################################################################

sub build {
    my ($self, $spec) = @_;

    # Check to make sure that only Class::Meta or a subclass is building
    # attribute accessors.
    my $caller = caller;
    $croak->("Package '$caller' cannot call " . __PACKAGE__ . "->build")
      unless UNIVERSAL::isa($caller, 'Class::Meta');

    # Just return if this attribute doesn't need accessors created for it.
    return $self if $self->{create} == Class::Meta::NONE;

    # Get the data type object and assemble the validation checks.
    my $type = Class::Meta::Type->new($self->{type});
    $type->build($spec->{package}, $self, delete $self->{create});

    # Create the attribute object get code reference.
    if ($self->{authz} >= Class::Meta::READ) {
        $self->{_get} = $type->make_attr_get($self);
    }

    # Create the attribute object set code reference.
    if ($self->{authz} >= Class::Meta::WRITE) {
        $self->{_set} = $type->make_attr_set($self);
    }

}

1;
__END__

=head1 DISTRIBUTION INFORMATION

This file was packaged with the Class-Meta-0.13 distribution.

=head1 BUGS

Please report all bugs via the CPAN Request Tracker at
L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Class-Meta>.

=head1 AUTHOR

David Wheeler <david@kineticode.com>

=head1 SEE ALSO

Other classes of interest within the Class::Meta distribution include:

=over 4

=item L<Class::Meta|Class::Meta>

=item L<Class::Meta::Class|Class::Meta::Class>

=item L<Class::Meta::Method|Class::Meta::Method>

=item L<Class::Meta::Constructor|Class::Meta::Constructor>

=item L<Class::Meta::Type|Class::Meta::Type>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002-2004, David Wheeler. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut
