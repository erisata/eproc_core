Introduction
========================================

Core `eproc` components. This application defines common `eproc` structure,
interfaces for its components and provides several implementations for them.
The most important module in this application is `eproc_fsm`. It defines a
behaviour for implementing persistent processes.

Please look at `eproc` application's description for more general description
and core principles.


Design
========================================

Message routing
----------------------------------------

*Typical route for an incoming message* is:

 1. Message is recognized and CorrelationKeys are extracted from it.
 2. CorrelationKeys are used to lookup InstanceId and InstanceGroup.
 3. InstanceGroup is used to find an instance registry.
 4. InstanceId is used to get ProcessId.
 5. Message is sent to a `eproc_fsm` process by ProcessId.

In a single-node setup, steps 2, 3, 4 and 5 are performed by single
call to the `gproc` based instance registry.

In a distributed setup, steps 1 and 2 are performed by a coordinator
on a node received the request, 3rd step is implemented by `riak_core`
and steps 4 and 5 are performed on a `vnode`. For more details look
at the `eproc_riak` application.

Modular design of the application allows to skip any number of the
first steps and proceed with the rest. E.g. only 5th step is used
when unit-testing `eproc_fsm` implementations.

*A route for an outgoing message* is much simplier:

 1. `eproc_fsm` implementation sends message to an outgoing channel
    via corresponding service.
 2. The channel forwards a message to the specified connector.
 3. The connector delivers the message in a protocol specific manner.

*Inter-process messages* are routed as follows:

 1. Inter-process communication service sends to the incoming message
    flow.
 2. If the message is sent with the InstanceId specified, lookup of the
    InstanceGroup is performed.
 3. Proceed with the incoming message scenario.

*Timer messages* are always handled in the scope of single instance
process only.

*Unrecognized messages* are dropped after several retries. The dropped
messages are stored in the `eproc_store` and marked accordingly.

*Failed messages* are linked to a transition defining state at which
the failure occured. The message are stored and marked accordingly.
The same goes for messages, that are received by an instance, that
is currently suspended.


Startup and shutdown procedures
----------------------------------------

Startup should be done in several phases:

  1. Initialization
  1.1. Setup application environment.
  1.2. Load channels.
  1.3. Load services.
  2. Startup
  2.1. Load all FSMs.
  2.2. Start outgoing channel flows.
  2.3. Register an application to the router.???
  2.4. Start all FSMs.
  2.5. Start incoming flows.

Shutdown procedures:

  1. Stop incoming flows.
  2. Stop all FSMs.
  3. Stop outgoing flows.
  4. Shutdown application.


Data model
----------------------------------------

This section describes a data model, used to persist a state of process
instances. The persistence layer is defined by the `eproc_store` behaviour.
The following are main entities and relations between them:

  * Instance
  * Transition
  * Timer
  * Key??
  * Message
  * MessageLink

Several implementations are designed for this data model. This application
provides an ETS based implementation that can be used to implement transient
processes. Its main purpose is to support unit-testing of `eproc_fsm`
implementations.

Other implementation is provided in the `eproc_riak` module. The provided
implementation is based on key-value store. The model here is denormalized
and most of the data is concentrated in the Transition bucket. Riak links
are used to define relations between the entities.



Using standalone `eproc_fsm`
========================================

Start Erlang with apropriate code path

    erl -pa deps/*/ebin ebin .

Compile the test FSM and prepare the environment:

    c("test/eproc_fsm_void.erl", [{i, "include"}]).
    application:load(eproc_core).
    application:set_env(eproc_core, store, {eproc_store_ets, []}).
    eproc_store_ets:start_link().

Run it:

    {ok, InstId} = eproc_fsm_void:create().
    {ok, _, PID} = eproc_fsm_void:start_link(InstId).
    ok = eproc_fsm_void:poke(InstId).


