package Myriad::Service;

use strict;
use warnings;

# VERSION

use Object::Pad;
use Future::AsyncAwait;

class Myriad::Service extends Myriad::Notifier;

use parent qw(
    Myriad::Service::Attributes
);

use utf8;

=encoding utf8

=head1 NAME

Myriad::Service - microservice coördination

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use Log::Any qw($log);
use List::Util qw(min);

# Only defer up to this many seconds between batch iterations
use constant MAX_EXPONENTIAL_BACKOFF => 2;

=head1 ATTRIBUTES

These methods return instance variables.

=head2 ryu

Provides a common L<Ryu::Async> instance.

=cut

has $ryu;
method ryu { $ryu }

=head2 redis

The L<Myriad::Storage> instance.

=cut

has $redis;
method redis { $redis }

=head2 myriad

The L<Myriad> instance which owns this service. Stored internally as a weak reference.

=cut

has $myriad;
method myriad { $myriad }

=head2 service_name

The name of the service, defaults to the package name.

=cut

has $service_name;
method service_name { $service_name //= lc(ref($self) =~ s{::}{_}gr) }

=head1 METHODS

=head2 configure

Populate internal configuration.

=cut

method configure (%args) {
    $redis = delete $args{redis} if exists $args{redis};
    $service_name = delete $args{name} if exists $args{name};
    Scalar::Util::weaken($myriad = delete $args{myriad}) if exists $args{myriad};
    $self->next::method(%args);
}

=head2 _add_to_loop

Apply this service to the current event loop.

This will trigger a number of actions:

=over 4

=item * initial startup

=item * first diagnostics check

=item * if successful, batch and subscription registration will occur

=back

=cut

has %active_batch;
method _add_to_loop ($loop) {
    $self->add_child(
        $ryu = Ryu::Async->new
    );

    if(my $batches = Myriad::Registry->batches_for(ref($self))) {
        for my $k (keys $batches->%*) {
            $log->tracef('Starting batch process %s for %s', $k, ref($self));
            my $code = $batches->{$k};
            my $src = $self->ryu->source(label => 'batch:' . $k);
            $active_batch{$k} = [
                $src,
                $self->process_batch($k, $code, $src)
            ];
        }
    }
    $self->next::method($loop);
}

async method process_batch ($k, $code, $src) {
    my $backoff;
    $log->tracef('Start batch processing for %s', $k);
    while(1) {
        await $src->unblocked;
        my $data = await $self->$code;
        if($data->@*) {
            $backoff = 0;
            $src->emit($_) for $data->@*;
            # Defer next processing, give other events a chance
            await $self->loop->delay_future(after => 0);
        } else {
            $backoff = min(MAX_EXPONENTIAL_BACKOFF, ($backoff || 0.02) * 2);
            $log->tracef('Batch for %s returned no results, delaying for %dms before retry', $k, $backoff * 1000.0);
            await $self->loop->delay_future(
                after => $backoff
            );
        }
    }
}

=head1 ASYNC METHODS

=head2 diagnostics

Runs any internal diagnostics.

=cut

async method diagnostics {
    return;
}

1;

=head1 AUTHOR

Binary Group Services Ltd. C<< BINARY@cpan.org >>.

See L<Myriad/CONTRIBUTORS> for full details.

=head1 LICENSE

Copyright Binary Group Services Ltd 2020. Licensed under the same terms as Perl itself.

