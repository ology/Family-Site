use utf8;
package Family::Site::Schema::Result::History;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Family::Site::Schema::Result::History

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 COMPONENTS LOADED

=over 4

=item * L<DBIx::Class::InflateColumn::DateTime>

=back

=cut

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 TABLE: C<history>

=cut

__PACKAGE__->table("history");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 who

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 20

=head2 what

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 256

=head2 when

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=head2 remote_addr

  data_type: 'varchar'
  default_value: (empty string)
  is_nullable: 0
  size: 15

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "who",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 20 },
  "what",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 256 },
  "when",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "remote_addr",
  { data_type => "varchar", default_value => "", is_nullable => 0, size => 15 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07045 @ 2016-01-28 19:46:39
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:SK2OliP4p5DOIJsf40H2yQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
