package Class::Meta;

# $Id: Meta.pm,v 1.11 2002/05/18 02:00:53 david Exp $

=head1 NAME

Class::Meta - Class Automation and Introspection

=head1 SYNOPSIS

  use Class::Meta;


=head1 DESCRIPTION



=cut

##############################################################################
# Dependencies                                                               #
##############################################################################
use strict;
use Carp ();

##############################################################################
# Constants                                                                  #
##############################################################################

# Visibility. These determine who can get metadata objects back from method
# calls.
use constant PRIVATE   => 0x01;
use constant PROTECTED => 0x02;
use constant PUBLIC    => 0x03;

# Authorization. These determine what kind of accessors (get, set, both, or
# none) are available for a given attribute or method.
use constant NONE      => 0x01;
use constant READ      => 0x02;
use constant WRITE     => 0x03;
use constant RDWR      => READ | WRITE;

# Method generation. These tell Class::Meta which accessors to create. Use
# NONE above for NONE. These will use the values in the auth argument by
# default. They're separate because sometimes an accessor needs to be built
# by hand, rather than custom-generated by Class::Meta, and the
# authorization needs to reflect that.
use constant GET       => 0x02;
use constant SET       => 0x03;
use constant GETSET    => GET | SET;

# Method and attribute context.
use constant CLASS     => 0x01;
use constant OBJECT    => 0x02;

# Metadata types. Used internally for tracking the different types of
# Class::Meta objects.
use constant ATTR      => 'attr';
use constant METH      => 'meth';
use constant CTOR      => 'ctor';

##############################################################################
# Dependencies that rely on the above constants                              #
##############################################################################
use Class::Meta::Type;
use Class::Meta::Class;
use Class::Meta::Attribute;
use Class::Meta::Method;
use Class::Meta::Constructor;

##############################################################################
# Package Globals                                                            #
##############################################################################
use vars qw($VERSION);
$VERSION = "0.01";

##############################################################################
# Function and Closure Prototypes                                            #
##############################################################################
my $add_memb;

##############################################################################
# Constructors                                                               #
##############################################################################
{
    my %classes;

    sub new {
        my ($pkg, $key, $class) = @_;
        # Class defaults to caller. Key defaults to class.
        $class ||= caller;
        $key ||= $class;

        # Make sure we haven't been here before.
        Carp::croak("Class '$class' already created")
          if exists $classes{$class};

        # Set up the definition hash.
        my $def = { key => $key,
                    pkg => $class };

        # Record the class' inheritance.
        my @isa;
        foreach my $is ($class, eval '@' . $class . "::ISA") {
            $def->{isa}{$is} = 1;
            push @isa, $is;
        }
        $def->{isa_ord} = \@isa;

        # Instantiate a Class object.
        $def->{class} = Class::Meta::Class->new($def);

        # Cache the definition.
        $classes{$class} = $def;

        # Return!
        return bless { pkg => $class }, ref $pkg || $pkg;
    }


##############################################################################
# Instance Methods                                                           #
##############################################################################
# Simple accessors.
    sub my_class { $classes{ $_[0]->{pkg} }->{class} }
    sub set_name { $classes{ $_[0]->{pkg} }->{class}{name} = $_[1] }
    sub set_desc { $classes{ $_[0]->{pkg} }->{class}{desc} = $_[1] }

##############################################################################
# add_attr()

    sub add_attr {
        Class::Meta::Attribute->new( $classes{ shift()->{pkg} }, @_);
    }

##############################################################################
# add_meth()

    sub add_meth {
        Class::Meta::Method->new( $classes{ shift()->{pkg} }, @_);
    }

##############################################################################
# add_ctor()

    sub add_ctor {
        Class::Meta::Constructor->new( $classes{ shift()->{pkg} }, @_);
    }

##############################################################################
# build()
    sub build {
        my $self = shift;
        my $def = $classes{ $self->{pkg} };
        no strict 'refs';

        # Build the attribute methods.
        foreach my $attr (@{$def->{build_attr_ord}}) {
        }

        # Build the constructors.
        foreach my $ctor (@{$def->{build_ctor_ord}}) {
            # Create a constructor.
            *{$def->{pkg} . '::' . $ctor->my_name } = sub {
                my $init = $_[1] || {};
                my $new = bless({}, ref $_[0] || $_[0]);

                foreach my $pobj (@{ $def->{attrs} }) {
                    my $p = $pobj->my_name;
                    if (exists $init->{$p}) {
                        # Assign the value passed in.
                        Carp::croak("Write access to attribute '$p' denied")
                          unless $pobj->my_vis > READ;
                        $pobj->set($new, delete $init->{$p});
                    } else {
                        # NOTE: Might have to construct a new object here.
                        $new->{$p} = $pobj->my_def;
                    }
                }
                if (my @attrs = keys %$init) {
                    # Attempts to assign to non-existent attributes fail.
                    my $c = $#attrs > 0 ? 'attributes' : 'attribute';
                    local $" = "', '";
                    Carp::croak("No such $c '@attrs' in $def->{pkg} "
                                . "objects");
                }
                return $new;
            };
        }

    }
}

##############################################################################
# Private closures                                                           #
##############################################################################

{
    my %types = ( &ATTR => { label => 'Attribute',
                             class  => 'Class::Meta::Attribute' },
                  &METH => { label => 'Method',
                             class => 'Class::Meta::Method' },
                  &CTOR => { label => 'Constructor',
                             class => 'Class::Meta::Constructor' }
                );

    $add_memb = sub {
        my ($type, $def, $spec) = @_;
        # Make sure that the name hasn't already been used.
        Carp::croak("Attribute '$spec->{name}' is not a valid attribute name "
                    . "-- only alphanumeric and '_' characters allowed")
          if $spec->{name} =~ /\W/;
        # Check to see if this member has been created already.
        Carp::croak("$types{$type}->{label} '$spec->{name}' already exists in "
                    . "class '$def->{class}'")
          if exists $def->{$type . 's'}{$spec->{name}};

        if ($type eq METH) {
            # Methods musn't conflict with constructors, either.
            Carp::croak("Construtor '$spec->{name}' already exists in class "
                        . "'$def->{class}'")
              if exists $def->{ctors}{$spec->{name}};
        } elsif ($type eq CTOR) {
            # Constructors musn't conflict with methods, either.
            Carp::croak("Method '$spec->{name}' already exists in class "
                        . "'$def->{class}'")
              if exists $def->{meths}{$spec->{name}};
        }

        # Create the member object.
        $spec->{class} = $def->{class};
        my $memb = $def->{$type. 's'}{$spec->{name}} =
          bless $spec, $types{$type}->{class};

        # Save the object if it needs accessors built. This will be cleaned
        # out when build() is called.
#       push @{ $def->{'build_' . $type . '_ord'} }, $mem
#         unless $spec->{gen} == NONE;

        # Just return the object if it's private.
        return $memb if $spec->{vis} == PRIVATE;

        # Preserve the order in which the attribute is declared.
        # Assume at least protected here.
        push @{ $def->{'prot_' . $type . '_ord'} }, $spec->{name};
        push @{ $def->{prot_ord} }, [$type, $spec->{name}];
        if ($spec->{vis} == PUBLIC) {
            # Save the position of the attribute from the public perspective.
            push @{ $def->{$type . '_ord'} }, $spec->{name};
            push @{ $def->{ord} }, [$type, $spec->{name}];
        }

        # Return the new attribute object.
        return $memb;
    };

    my %attr_defs = ( vis => GETSET,
                      

                    );

    my $set_attr = sub {
        my ($type, $def, $spec) = @_;
        $spec->{vis} ||= $spec->{auth} || GETSET if $type ne METH;

    };
}

1;
__END__

=head1 TO DO

=over 4

=item *

Make it possible to subclass all of the member classes, as well as
Class::Meta::Class, of course.

=item *

Add localization using Locale::Maketext.

=back

=head1 AUTHOR

David Wheeler <david@wheeler.net>

=head1 SEE ALSO

L<Class::Contract|Class::Contract>

=head1 COPYRIGHT AND LICENSE

Copyright (c) 2002, David Wheeler. All Rights Reserved.

This module is free software; you can redistribute it and/or modify it under the
same terms as Perl itself.

=cut
