#
#  Copyright 2009 10gen, Inc.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#

package MongoDB::Collection;
our $VERSION = '0.28_01';

# ABSTRACT: A Mongo Collection

=head1 NAME

MongoDB::Collection - A Mongo Collection

=cut

use Tie::IxHash;
use Any::Moose;

has _database => (
    is       => 'ro',
    isa      => 'MongoDB::Database',
    required => 1,
    handles  => [qw/query find_one insert update remove ensure_index batch_insert/],
);

=head1 ATTRIBUTES

=head2 name

The name of the collection.

=cut

has name => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=head2 full_name

The full_name of the collection, including the namespace of the database it's
in.

=cut

has full_name => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_full_name',
);

sub _build_full_name {
    my ($self) = @_;
    my $name    = $self->name;
    my $db_name = $self->_database->name;
    return "${db_name}.${name}";
}

=head1 STATIC METHODS

=head2 to_index_string ($keys)

    $name = MongoDB::Collection::to_index_string({age : 1});

Takes a L<Tie::IxHash>, hash reference, or array reference.  Converts it into
an index string.

=cut

sub to_index_string {
    my $keys = shift;

    my @name;
    if (ref $keys eq 'ARRAY' ||
        ref $keys eq 'HASH' ) {
        
        while ((my $idx, my $d) = each(%$keys)) {
            push @name, $idx;
            push @name, $d;
        }
    }
    elsif (ref $keys eq 'Tie::IxHash') {
        my @ks = $keys->Keys;
        my @vs = $keys->Values;

        @vs = $keys->Values;
        for (my $i=0; $i<$keys->Length; $i++) {
            push @name, $ks[$i];
            push @name, $vs[$i];
        }
    }
    else {
        confess 'expected Tie::IxHash, hash, or array reference for keys';
    }

    return join("_", @name);
}

=head1 METHODS

=head2 query ($query, \%attrs?)

    my $cursor = $collection->query({ i => { '$gt' => 42 } });

    my $cursor = $collection->query({ }, { limit => 10, skip => 10 });

    my $cursor = $collection->query(
        { location => "Vancouver" },
        { sort_by  => { age => 1 } },
    );

Executes the given C<$query> and returns a C<MongoDB::Cursor> with the results.
C<$query> can be a hash reference, L<Tie::IxHash>, or array reference (with an
even number of elements).  A hash reference of attributes may be passed as the 
second argument.

Valid query attributes are:

=over 4

=item limit

Limit the number of results.

=item skip

Skip a number of results.

=item sort_by

Order results.

=back

=head2 find_one ($query, $fields?)

    my $object = $collection->find_one({ name => 'Resi' });
    my $object = $collection->find_one({ name => 'Resi' }, { name => 1, age => 1});

Executes the given C<$query> and returns the first object matching it.
C<$query> can be a hash reference, L<Tie::IxHash>, or array reference (with an
even number of elements).  If C<$fields> is specified, the resulting document 
will only include the fields given (and the C<_id> field) which can cut down on
wire traffic.

=head2 insert (\%object, \%options?)

    my $id1 = $coll->insert({ name => 'mongo', type => 'database' });
    my $id2 = $coll->insert({ name => 'mongo', type => 'database' }, {safe => 1});

Inserts the given C<$object> into the database and returns it's id
value. C<$object> can be a hash reference, a reference to an array with an
even number of elements, or a L<Tie::IxHash>.  The id is the C<_id> value 
specified in the data or a L<MongoDB::OID>.

The optional C<$options> parameter can be used to specify if this is a safe 
insert.  A safe insert will check with the database if the insert succeeded and
confess that it did not, if an error occured.

=head2 batch_insert (\@array, \%options)

    my @ids = $collection->batch_insert([{name => "Joe"}, {name => "Fred"}, {name => "Sam"}]);

Inserts each of the documents in the array into the database and returns an
array of their _id fields.

The optional C<$options> parameter can be used to specify if this is a safe 
insert.  A safe insert will check with the database if the insert succeeded and
confess that it did not, if an error occured.

=head2 update (\%criteria, \%object, \%options?)

    $collection->update({'x' => 3}, {'$inc' => {'count' => -1} }, {"upsert" => 1, "multiple" => 1});

Updates an existing C<$object> matching C<$criteria> in the database. 

C<update> can take a hash reference of options.  The options 
currently supported are:

=over 

=item C<upsert> 
If no object matching C<$criteria> is found, C<$object> will be inserted.

=item C<multiple>
All of the documents that match C<$criteria> will be updated, not just 
the first document found. (Only available with database version 1.1.3 and 
newer.)

=back

=head2 remove (\%query?, $just_one?)

    $collection->remove({ answer => { '$ne' => 42 } });

Removes all objects matching the given C<$query> from the database. If no
parameters are given, removes all objects from the collection (but does not
delete indexes, as C<MongoDB::Collection::drop> does).  Boolean parameter 
C<$just_one> causes only one matching document to be removed.

=head2 ensure_index (\%keys, $options?)

    use boolean;
    $collection->ensure_index({"foo" => 1, "bar" => -1}, { unique => true });

Makes sure the given C<$keys> of this collection are indexed. C<$keys> can be an
array reference, hash reference, or C<Tie::IxHash>.  C<Tie::IxHash> is prefered
for multi-key indexes, so that the keys are in the correct order.  1 creates an 
ascending index, -1 creates a descending index.  

The second parameter gives index options.  Available options are:

=over

=item C<unique => boolean>

By default, indexes are not unique. To create a unique index, pass 
C<"unique" => true>.  C<true> can be L<boolean::true> or any other true value.

=item C<drop_dups => boolean>

If a unique index is being created on an existing set of data that has duplicate
values, creating the index will fail.  To force the index creation by deleting 
duplicate values, use this option.  Again, any value that evaluates to true will
work.

=back

=cut

around qw/query find_one insert update remove ensure_index batch_insert/ => sub {
    my ($next, $self, @args) = @_;
    return $self->$next($self->_query_ns, @args);
};

sub _query_ns {
    my ($self) = @_;
    return $self->name;
}

=head2 count ($query?)

    my $n_objects = $collection->count({ name => 'Bob' });

Counts the number of objects in this collection that match the given C<$query>. 
If no query is given, the total number of objects in the collection is returned.

=cut

sub count {
    my ($self, $query) = @_;
    $query ||= {};

    my $obj;
    eval {
        $obj = $self->_database->run_command({
            count => $self->name,
            query => $query,
        });
    };

    if ($obj =~ m/^ns missing/) {
        return 0;
    }

    return $obj->{n};
}

=head2 validate

    $collection->validate;

Asks the server to validate this collection.
Returns a hash of the form:

    {
        'ok' => '1',
        'ns' => 'foo.bar',
        'result' => info
    }

where C<info> is a string of information 
about the collection.

=cut

sub validate {
    my ($self, $scan_data) = @_;
    $scan_data = 0 unless defined $scan_data;
    my $obj = $self->_database->run_command({ validate => $self->name });
}

=head2 drop_indexes

    $collection->drop_indexes;

Removes all indexes from this collection.

=cut

sub drop_indexes {
    my ($self) = @_;
    return $self->drop_index('*');
}

=head2 drop_index ($index_name)

    $collection->drop_index('foo_1');

Removes an index called C<$index_name> from this collection.
Use C<MongoDB::Collection::get_indexes> to find the index name.

=cut

sub drop_index {
    my ($self, $index_name) = @_;
    my $t = tie(my %myhash, 'Tie::IxHash');
    %myhash = ("deleteIndexes" => $self->name, "index" => $index_name);
    return $self->_database->run_command($t);
}

=head2 get_indexes

    my @indexes = $collection->get_indexes;

Returns a list of all indexes of this collection.
Each index contains C<ns>, C<name>, and C<key>
fields of the form:

    {
        'ns' => 'db_name.collection_name',
        'name' => 'index_name',
        'key' => {
            'key1' => dir1,
            'key2' => dir2,
            ...
            'keyN' => dirN
        }
    }

where C<dirX> is 1 or -1, depending on if the
index is ascending or descending on that key.

=cut

sub get_indexes {
    my ($self) = @_;
    return $self->_database->get_collection('system.indexes')->query({
        ns => $self->full_name,
    })->all;
}

=head2 drop

    $collection->drop;

Deletes a collection as well as all of its indexes.

=cut

sub drop {
    my ($self) = @_;
    $self->_database->run_command({ drop => $self->name });
    return;
}

no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;

=head1 AUTHOR

  Kristina Chodorow <kristina@mongodb.org>
