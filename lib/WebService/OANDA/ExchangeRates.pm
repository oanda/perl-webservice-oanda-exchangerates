package WebService::OANDA::ExchangeRates;
# ABSTRACT: A Perl interface to the OANDA Exchange Rates API

use JSON::XS;
use LWP::UserAgent;
use Moo;
use Type::Params qw{ compile };
use Types::Standard qw{
    slurpy
    ArrayRef
    Dict
    Int
    Optional
    Str
    StrMatch
};
use Type::Utils qw{ declare as where coerce from via enum};
use Types::URI qw{ Uri };
use WebService::OANDA::ExchangeRates::Response;

use vars qw($VERSION);
$VERSION = "0.001";

has base_url => (
    is       => 'ro',
    isa      => Uri,
    coerce   => Uri->coercion,
    default  => 'https://www.oanda.com/rates/api/v1/',
    required => 1,
);
has proxy => (
    is        => 'ro',
    isa       => Uri,
    coerce    => Uri->coercion,
    predicate => 1,
);
has timeout => ( is => 'ro', isa => Int, predicate => 1 );
has api_key => ( is => 'ro', isa => Str, required  => 1 );
has user_agent => ( is => 'ro', lazy => 1, builder => 1, init_arg => undef );

has _rates_validator => ( is => 'ro', required => 1, builder => 1 );

sub _build__rates_validator {

    # TYPES FOR VALIDATOR
    my $Currency = declare as StrMatch[qr{^[A-Z]{3}$}];
    my $Quotes   = declare as ArrayRef[$Currency];
    coerce $Quotes, from Str, via { [$_] };
    my $Date = declare as StrMatch[qr{^\d\d\d\d-\d\d-\d\d$}];
    my $Fields = declare as ArrayRef[Str];
    coerce $Fields, from Str, via { [$_] };
    my $DecimalPlaces = StrMatch[qr{^(?:\d+|all)$}];

    my %validators = (
        base_currency   => $Currency,
        quote           => $Quotes,
        date            => $Date,
        start           => $Date,
        end             => $Date,
        fields          => $Fields,
        decimal_places  => $DecimalPlaces,
    );

    return sub {
        my %params = @_;

        my %result = ();
        die "missing required parameter: base_currency"
            unless exists $params{base_currency};

        foreach my $key ( keys %params ) {
            my $type = $validators{$key};
            die "invalid parameter: $key" unless $type;
            my $val = $params{$key};
            $val = $type->coerce($val) if $type->has_coercion;
            if ( ! $type->check($val) ) {
                $val = JSON::XS::encode_json($val) if ref $val;
                die "invalid value: $key = ($val)";
            }
            $result{$key} = $val;
        }
        return \%result;

    }
}

sub _build_user_agent {
    my $self = shift;

    my %options = ( agent => sprintf '%s/%s', __PACKAGE__, $VERSION );

    # LWP::UA forces hostname verification by default in newer versions
    # turn off for simplification;
    $options{ssl_opts} = { verify_hostname => 0 }
        if $self->base_url->scheme eq 'https';
    $options{timeout} = $self->timeout if $self->has_timeout;

    my $ua = LWP::UserAgent->new(%options);

    # set auth header
    $ua->default_header(
        Authorization => sprintf 'Bearer %s', $self->api_key
    );

    # set the proxy if needed
    # LWP:UserAgent will use PERL_LWP_ENV_PROXY if set automatically
    $ua->proxy( $self->base_url->scheme, $self->proxy ) if $self->has_proxy;

    return $ua;
}

# GET /currencies.json
sub get_currencies {
    my $self = shift;

    my $response = $self->_get_request('currencies.json');

    # convert arrayref[hashref] into hashref
    if ( $response->is_success && exists $response->data->{currencies}) {
        $response->data({
            map { $_->{code} => $_->{description} }
                @{$response->data->{currencies}}
        });
    }

    return $response;
}

# GET /rates/XXX.json
sub get_rates {
    my $self = shift;
    my $params = $self->_rates_validator->(@_);

    my $base_currency = delete $params->{base_currency};
    return $self->_get_request(['rates', $base_currency . '.json'], $params);
}

# GET /remaining_quotes.json
sub get_remaining_quotes {
    my $self = shift;
    return $self->_get_request('remaining_quotes.json');
}

sub _get_request {
    my ( $self, $path, $params ) = @_;

    my $uri = $self->base_url->clone->canonical;

    # build the new path
    $path = [$path] unless ref $path eq 'ARRAY';
    my @new_path = grep { $_ ne '' } ($uri->path_segments, @{$path});
    $uri->path_segments( @new_path );

    # set query params
    $params = {} unless defined $params;
    $uri->query_form(%{$params});

    my $response = $self->user_agent->get( $uri->as_string );
    return WebService::OANDA::ExchangeRates::Response->new(
        http_response => $response );
}

1;

__END__

