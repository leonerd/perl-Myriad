use strict;
use warnings;

use Test::More;
use Test::Fatal;

use Log::Any::Adapter qw(TAP);
use Log::Any qw($log);

$log->infof('starting');

# Assorted syntax helper checks. So much eval.

subtest 'enables strict' => sub {
    fail('eval should not succeed with global var') if eval(q{
        package local::strict::vars;
        use microservice;
        $x = 123;
    });
    like($@, qr/Global symbol \S+ requires explicit package/, 'strict vars enabled');
    fail('eval should not succeed with symbolic refs') if eval(q{
        package local::strict::refs;
        use microservice;
        my $var = 123;
        my $name = 'var';
        print $$var;
    });
    like($@, qr/as a SCALAR ref/, 'strict refs enabled');
    fail('eval should not succeed with poetry') if eval(q{
        package local::strict::subs;
        use microservice;
        MissingSub;
    });
    like($@, qr/Bareword \S+ not allowed/, 'strict subs enabled');
};

subtest 'disables indirect object syntax' => sub {
    fail('indirect call should be fatal') if eval(q{
        package local::indirect;
        use microservice;
        indirect { 'local::indirect' => 1 };
    });
    like($@, qr/Indirect call/, 'no indirect enabled');
};

subtest 'try/catch available' => sub {
    is(eval(q{
        package local::try;
        use microservice;
        try { die 'test' } catch { 'ok' }
    }), 'ok', 'try/catch supported') or diag $@;
};

subtest 'dynamically available' => sub {
    is(eval(q{
        package local::dynamically;
        use microservice;
        my $x = "ok";
        {
         dynamically $x = "fail";
        }
        $x
    }), 'ok', 'dynamically supported') or diag $@;
};

subtest 'async/await available' => sub {
    isa_ok(eval(q{
        package local::asyncawait;
        use microservice;
        async sub example {
         await Future->new;
        }
        example();
    }), 'Future') or diag $@;
};

subtest 'utf8 enabled' => sub {
    local $TODO = 'probably not a valid test, fixme';
    is(eval(qq{
        package local::unicode;
        use microservice;
        "\x{2084}"
    }), "\x{2084}", 'utf8 enabled') or diag $@;
};

subtest 'Log::Any imported' => sub {
    is(eval(q{
        package local::logging;
        use microservice;
        $log->tracef("test");
        1;
    }), 1, '$log is available') or diag $@;
};

subtest 'Object::Pad' => sub {
    isa_ok(eval(q{
        package local::pad;
        use microservice;
        method test { $self->can('test') ? 'ok' : 'not ok' }
        async method test_async { $self->can('test_async') ? 'ok' : 'not ok' }
        __PACKAGE__
    }), 'IO::Async::Notifier') or diag $@;
    isa_ok('local::pad', 'Myriad::Service');
    my $obj = new_ok('local::pad');
    can_ok($obj, 'test');
    is($obj->test, 'ok', 'we find our own methods');
    is(exception {
        $obj->diagnostics
    }, undef, 'we created our own happiness');
};

subtest 'attributes' => sub {
    isa_ok(eval(q{
        package local::attributes;
        use microservice;
        method test:RPC { $self->can('test') ? 'ok' : 'not ok' }
        __PACKAGE__
    }), 'IO::Async::Notifier') or diag $@;
    my $obj = new_ok('local::attributes');
    can_ok($obj, 'test');
    is($obj->test, 'ok', 'we find our own methods');
};
done_testing;

