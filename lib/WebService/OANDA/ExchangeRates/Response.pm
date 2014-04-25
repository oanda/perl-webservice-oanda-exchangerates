package WebService::OANDA::ExchangeRates::Response;

use Moo;

use HTTP::Response;
use JSON::XS qw{decode_json};
use Try::Tiny;

has http_response => (
    is  => 'rw',
    handles => {
        is_success  => 'is_success',
        is_error    => 'is_error',
        raw_data    => 'content',
        http_status => 'code',
    },
    required => 1,
);

has data => ( is  => 'rw' );

sub BUILD {
    my $self = shift;
    my $data;

    try {
        $data = JSON::XS::decode_json( $self->raw_data );
    }
    catch {
        $data = {
            code => undef,
            message => sprintf(
                'Failed to decode content(%s): $%s', $self->raw_data, $_
            )
        };

        # if we failed to decode the json on a successful query, we'll consider
        # this an outlier and force a 500
        if ($self->is_success) {
            $self->http_response(
                HTTP::Response->new(500, undef, undef, $self->raw_data)
            );
        }

    };

    $self->data($data);
}

sub error_message {
    my $self = shift;

    return unless $self->is_error;
    return $self->data->{message};
}

sub error_code {
    my $self = shift;
    return unless $self->is_error;
    return $self->data->{code};
}

1;