#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 2;

package MyClass;
use Moose;
with 'Data::Serializable';

package main;

my $obj = MyClass->new( serializer_module => 'JSON' );
my $json = $obj->serialize( "Foo" );
is($json, '{"_serialized_object":"Foo"}', '"Foo" serializes correctly');
my $str = $obj->deserialize( $json );
is($str, 'Foo', '"Foo" deserializes correctly');
