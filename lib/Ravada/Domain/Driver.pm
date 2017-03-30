package Ravada::Domain::Driver;

use warnings;
use strict;

use Moose;

has 'domain' => (
    isa => 'Any'
    ,is => 'ro'
);

has 'id' => (
    isa => 'Int'
    ,is => 'ro'
);

##############################################################################

our $TABLE_DRIVERS = "domain_drivers_types";
our $TABLE_OPTIONS= "domain_drivers_options";

##############################################################################

sub get_value {
    my $self = shift;
    return $self->domain->get_driver($self->name);
}

sub name {
    my $self = shift;
    return $self->_data('name');
}

sub _data {
    my $self = shift;
    my $field = shift or confess "Missing field name";

    return $self->{_data}->{$field} if exists $self->{_data}->{$field};
    $self->{_data} = $self->_select_driver_db( id => $self->id);

    confess "No DB info for driver ".$self->id      if !$self->{_data};
    confess "No field $field in drivers "           if !exists$self->{_data}->{$field};

    return $self->{_data}->{$field};
}

sub _select_driver_db {
    my $self = shift;
    my %args = @_;

    if (!keys %args) {
        %args =( id => $self->id );
    }

    my $sth = Ravada::DB->instance->dbh->prepare(
        "SELECT * FROM $TABLE_DRIVERS WHERE ".join(",",map { "$_=?" } sort keys %args )
    );
    $sth->execute(map { $args{$_} } sort keys %args);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $self->{_data} = $row;
    return $row if $row->{id};

}

sub get_options {
    my $self = shift;

    my $query = "SELECT * from $TABLE_OPTIONS WHERE id_driver_type=? ORDER by name";

    my $sth = Ravada::DB->instance->dbh->prepare($query);
    $sth->execute($self->id);

    my @ret;
    while (my $row = $sth->fetchrow_hashref) {
        push @ret,($row);
    }
    return @ret;

}

1;
