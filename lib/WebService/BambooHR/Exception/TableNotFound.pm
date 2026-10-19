package WebService::BambooHR::Exception::TableNotFound;

use 5.010;
use Moo;
extends 'WebService::BambooHR::Exception';

=head1 NAME

WebService::BambooHR::Exception::TableNotFound - no BambooHR table has the configured alias

=head1 DESCRIPTION

Subclass of L<WebService::BambooHR::Exception> (which composes Throwable). Callers must supply
C<method>, C<message>, C<code>, C<reason>, C<filename> and C<line_number>: the base class's
C<as_string> concatenates all of them. L<WebService::BambooHR::FieldRegistry> does.

=cut

has 'label' => ( is => 'ro' );

1;
