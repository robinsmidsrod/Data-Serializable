use strict;
use warnings;
use 5.006; # Found with Perl::MinimumVersion

package Data::Serializable;
use Moose::Role;

# ABSTRACT: Moose role that adds serialization support to any class

use Module::Runtime ();
use Carp qw(croak confess);

# Wrap data structure that is not a hash-ref
sub _wrap_invalid {
    my ($module, $obj) = @_;
    # JSON doesn't know how to serialize anything but hashrefs
    # FIXME: Technically we should allow array-ref, as JSON standard allows it
    if ( $module eq 'Data::Serializer::JSON' ) {
        return ref($obj) eq 'HASH' ? $obj : { '_serialized_object' => $obj };
    }
    # XML::Simple doesn't know the difference between empty string and undef
    if ( $module eq 'Data::Serializer::XML::Simple' ) {
        return { '_serialized_object_is_undef' => 1 } unless defined($obj);
        return $obj if ref($obj) eq 'HASH';
        return { '_serialized_object' => $obj };
    }
    return $obj;
}

# Unwrap JSON previously wrapped with _wrap_invalid()
sub _unwrap_invalid {
    my ($module, $obj) = @_;
    if ( $module eq 'Data::Serializer::JSON' ) {
        if ( ref($obj) eq 'HASH' and keys %$obj == 1 and exists( $obj->{'_serialized_object'} ) ) {
            return $obj->{'_serialized_object'};
        }
        return $obj;
    }
    # XML::Simple doesn't know the difference between empty string and undef
    if ( $module eq 'Data::Serializer::XML::Simple' ) {
        if ( ref($obj) eq 'HASH' and keys %$obj == 1 ) {
            if ( exists $obj->{'_serialized_object_is_undef'}
                and $obj->{'_serialized_object_is_undef'} )
            {
                return undef; ## no critic qw(Subroutines::ProhibitExplicitReturnUndef)
            }
            return $obj->{'_serialized_object'} if exists $obj->{'_serialized_object'};
            return $obj;
        }
        return $obj;
    }
    return $obj;
}

=attr throws_exception

Defines if methods should throw exceptions or return undef. Default is to throw exceptions.
Override default value like this:

    has '+throws_expection' => ( default => 0 );

=cut

has 'throws_exception' => (
    is      => 'rw',
    isa     => 'Bool',
    default => 1,
);

=attr serializer_module

Name of a predefined module that you wish to use for serialization.
Any submodule of L<Data::Serializer> is automatically supported.
The built-in support for L<Storable> doesn't require L<Data::Serializer>.

=cut

has "serializer_module" => (
    is      => 'rw',
    isa     => 'Str',
    default => 'Storable',
);

=attr serializer

If none of the predefined serializers work for you, you can install your own.
This should be a code reference that takes one argument (the message to encode)
and returns a scalar back to the caller with the serialized data.

=cut

has "serializer" => (
    is      => 'rw',
    isa     => 'CodeRef',
    lazy    => 1,
    builder => '_build_serializer',
);

# Default serializer uses Storable
sub _build_serializer { ## no critic qw(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;

    # Figure out full package name of serializer
    my $module = $self->serializer_module;
    if( $module ne 'Storable' ) {
        $module = 'Data::Serializer::' . $module;
    }

    # Make sure serializer module is loaded
    Module::Runtime::require_module( $module );

    # Just return sub if using default
    if ( $module eq 'Storable' ) {
        return sub {
            return Storable::nfreeze( \( $_[0] ) );
        };
    }

    unless ( $module->isa('Data::Serializer') ) {
        confess("Serializer module '$module' is not a subclass of Data::Serializer");
    }
    my $handler = bless {}, $module; # subclasses apparently doesn't implement new(), go figure!
    unless ( $handler->can('serialize') ) {
        confess("Serializer module '$module' doesn't implement the serialize() method");
    }

    # Return the specified serializer if we know about it
    return sub {
        # Data::Serializer::* has an instance method called serialize()
        return $handler->serialize(
            _wrap_invalid( $module, $_[0] )
        );
    };

}

=attr deserializer

Same as serializer, but to decode the data.

=cut

has "deserializer" => (
    is      => 'rw',
    isa     => 'CodeRef',
    lazy    => 1,
    builder => '_build_deserializer',
);

# Default deserializer uses Storable
sub _build_deserializer { ## no critic qw(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self) = @_;

    # Figure out full package name of serializer
    my $module = $self->serializer_module;
    if( $module ne 'Storable' ) {
        $module = 'Data::Serializer::' . $module;
    }

    # Make sure serializer module is loaded
    Module::Runtime::require_module( $module );

    # Just return sub if using default
    if ( $module eq 'Storable' ) {
        return sub {
            return if @_ > 0 and not defined( $_[0] );
            return ${ Storable::thaw( $_[0] ) };
        };
    }

    unless ( $module->isa('Data::Serializer') ) {
        confess("Serializer module '$module' is not a subclass of Data::Serializer");
    }
    my $handler = bless {}, $module; # subclasses apparently doesn't implement new(), go figure!
    unless ( $handler->can('deserialize') ) {
        confess("Serializer module '$module' doesn't implement the deserialize() method");
    }

    # Return the specified serializer if we know about it
    return sub {
        return if @_ > 0 and not defined( $_[0] );
        # Data::Serializer::* has an instance method called deserialize()
        return _unwrap_invalid(
            $module, $handler->deserialize( $_[0] )
        );
    };

}

=method serialize($message)

Runs the serializer on the specified argument.

=cut

sub serialize {
    my ($self,$message) = @_;

    # Serialize data
    my $serialized = eval { $self->serializer->($message); };
    if ($@) {
        croak("Couldn't serialize data: $@") if $self->throws_exception;
        return; # FAIL
    }

    return $serialized;
}

=method deserialize($message)

Runs the deserializer on the specified argument.

=cut

sub deserialize {
    my ($self,$message)=@_;

    # De-serialize data
    my $deserialized = eval { $self->deserializer->($message); };
    if ($@) {
        croak("Couldn't deserialize data: $@") if $self->throws_exception;
        return; # FAIL
    }

    return $deserialized;
}

no Moose::Role;
1;

__END__

=head1 SYNOPSIS

    package MyClass;
    use Moose;
    with 'Data::Serializable';
    no Moose;

    package main;
    my $obj = MyClass->new( serializer_module => 'JSON' );
    my $json = $obj->serialize( "Foo" );
    ...
    my $str = $obj->deserialize( $json );

=head1 DESCRIPTION

A Moose-based role that enables the consumer to easily serialize/deserialize data structures.
The default serializer is L<Storable>, but any serializer in the L<Data::Serializer> hierarchy can
be used automatically. You can even install your own custom serializer if the pre-defined ones
are not useful for you.

=head1 SEE ALSO

=for :list
* L<Moose::Manual::Roles>
* L<Data::Serializer>
