%/--------------------------------------------------------------------
%| Copyright 2013-2014 Erisata, UAB (Ltd.)
%|
%| Licensed under the Apache License, Version 2.0 (the "License");
%| you may not use this file except in compliance with the License.
%| You may obtain a copy of the License at
%|
%|     http://www.apache.org/licenses/LICENSE-2.0
%|
%| Unless required by applicable law or agreed to in writing, software
%| distributed under the License is distributed on an "AS IS" BASIS,
%| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%| See the License for the specific language governing permissions and
%| limitations under the License.
%\--------------------------------------------------------------------

%%
%%  Common data types for the `eproc_fsm`.
%%

-type proplist()        :: [{term(), term()}].
-type datetime()        :: calendar:datetime().     % {Date, Time} in UTC
-type timestamp()       :: erlang:timestamp().      % {Mega, Secs, Micro}
-type duration()        :: integer().               % in ms.

%%
%%  OTP standard process reference. See `gen_server` or
%%  other OTP behaviour for more details.
%%
-type otp_ref() ::
    pid() |
    atom() |
    {atom(), atom()} |
    {global, atom()} |
    {via, module(), term()}.

-type inst_id()         :: eproc_fsm:id().
-type fsm_ref()         :: {inst, inst_id()} | {name, term()}.  % TODO: Key should not be used in runtime registration: {key, term()}.
-type inst_name()       :: term().
-type inst_group()      :: eproc_fsm:group().
-type inst_status()     :: running | suspended | done | failed | killed.
-type codec_ref()       :: eproc_codec:ref().
-type store_ref()       :: eproc_store:ref().
-type registry_ref()    :: eproc_registry:ref().
-type trn_nr()          :: integer().
-type msg_id()          :: term().
-type party()           :: {inst, inst_id()} | {ext, term()}.
-type scope()           :: list().

%%
%%  This record is modelled after the LDAP `inetOrgPersor` object class,
%%  using subset of the attributes and uses LDAP syntaxt to represent them.
%%
-record(user, {
    dn  :: binary(),    %% Distinguashed name in the LDAP format.
    cn  :: binary(),    %% Common name.
    uid :: binary()     %% Username.
}).


%%
%%  TODO: Docs.
%%
-record(user_action, {
    user    :: #user{},
    time    :: timestamp(),
    comment :: binary()
}).


%%
%%  Identifies party and its type that sent the corresponding event.
%%
-type event_src() ::
    {inst, inst_id()} |
    {Type :: atom(), Id :: term()}.


%%
%%  A reference to a message, that can be attached to a specific
%%  transition.
%%
-record(msg_ref, {
    id          :: msg_id(),                    %% Unique identifier.
    peer        :: event_src()                  %% Sender or receiver of the message.
}).


%%
%%  A message, that was sent from a sender to a receiver.
%%  At least one of them will be an FSM instance.
%%
-record(message, {
    id          :: msg_id(),                    %% Unique identifier.
    sender      :: event_src(),                 %% Source.
    receiver    :: event_src(),                 %% Destination.
    resp_to     :: msg_id() | undefined,        %% Indicates a request message, if thats a response to it.
    date        :: timestamp(),                 %% Time, when message was sent.
    body        :: term()                       %% Actual message.
}).


%%
%%  Denotes a message or its reference.
%%
-type msg_ref() :: #message{} | #msg_ref{}.


%%
%%  Triggers can be of different types. Several types are provided
%%  by the core implementation and other can be added by a user.
%%  FSM attribute implementations can define own trigger types.
%%  For example, the timer trigger is implemented as an attribute trigger.
%%
-type trigger_type() :: event | sync | timer | admin | atom().


%%
%%  Trigger initiates FSM transitions. Event (message) is the core
%%  attribute of the trigger. Additionally event source, type and
%%  other attributes are used to define the trigger more preciselly.
%%
%%  Example triggers:
%%
%%      #trigger_spec{type = event, source = {inst, 12364},    message = any,             sync = false},
%%      #trigger_spec{type = event, source = {connector, api}, message = any,             sync = false},
%%      #trigger_spec{type = sync,  source = {connector, api}, message = any,             sync = true},
%%      #trigger_spec{type = timer, source = my_timer,         message = timeout,         sync = false},
%%      #trigger_spec{type = admin, source = "John Doe",       message = "Problem fixed", sync = false}.
%%
%%  TODO: Rename `{inst, inst_id()}` to `{fsm, inst_id()}`.
%%  This structure is transient, not intended for storing in a DB.
%%
-record(trigger_spec, {
    type            :: trigger_type(),          %% Type of the trigger.
    source          :: event_src(),             %% Party, initiated the trigger, event source, admin name.
    message         :: term(),                  %% Event message / body.
    sync = false    :: boolean(),               %% True, if the trigger expects an immediate response.
    reply_fun       :: undefined | function(),  %% Function used to sent response if the trigger is sync.
    src_arg         :: boolean()                %% If set to true, event source will be passed to an FSM implementation.
}).


%%
%%  TODO: Docs
%%
-record(attribute, {
    inst_id,
    attr_id,
    module,
    name,
    scope,
    data        :: term(),                  %% Custom attribute data.
    from        :: trn_nr(),                %% Transition at which the attribute was set.
    upds = []   :: [trn_nr()],              %% Transitions at which the attribute was updated.
    till        :: trn_nr() | undefined,    %% Transition at which the attribute was removed.
    reason      :: term()                   %%  Reason for the attribute removal.
}).


%%
%%  TODO: Docs
%%
-record(attr_action, {
    module,
    attr_id,
    action  ::
        {create, Name :: term(), Scope :: term(), Data :: term()} |
        {update, NewScope :: term(), NewData :: term()} |
        {remove, Reason :: (
            {scope, NewSName :: term()} |
            {user, UserReason :: term()}
        )}
}).


%%
%%  Describes a manual state update.
%%  An administrator can update the process state and its
%%  atributes while the FSM is in the suspended mode.
%%
%%  The suspension record is only needed on startup, if it has
%%  `Updated =/= undefined` for the current transition. When starting
%%  the FSM with such a record present, new transition will be created
%%  with the `sname` and `sdata` copied from it. This way the suspension
%%  record will became not active (not referring the last transition).
%%
%%  If resume is failing due to updated data or attribute actions, the process
%%  is marked as suspended again, but no new suspension record is created.
%%  The failure will be appended to the list of resume failures ('res_faults').
%%
-record(inst_suspension, {
    id          :: integer(),       %% Suspension ID, must not be used for record sorting.
    inst_id     :: inst_id(),       %% FSM instance, that was suspended.
    trn_nr      :: trn_nr(),        %% Transition at which the instance was suspended.
    suspended   :: timestamp(),     %% When the FSM was suspended.
    reason      :: #user_action{} | {fault, Reason :: term()} | {impl, Reason :: binary()},
    updated     :: #user_action{} | undefined,  %% Who, when, why updated the state.
    upd_sname   :: term() | undefined,          %% FSM state name set by an administrator.
    upd_sdata   :: term() | undefined,          %% FSM state data set by an administrator.
    upd_attrs   :: [#attr_action{}] | undefined,%% Manual attribute changes.
    resumed     :: [{                           %% Multiple attempts to resume prcess can exist.
        #user_action{},                         %% Who, when, why resumed the FSM.
        FailTime :: timestamp() | undefined,    %% Failure timestamp, if any.
        FailReason :: term()                    %% Failure description.
    }]
}).

%%
%%  Describes single transition of a particular instance.
%%  This structure describes transition and the target state.
%%
-record(transition, {
    inst_id     :: inst_id(),   %% Id of an instance the transition belongs to.
    number      :: trn_nr(),    %% Transition number in the FSM (starts at 0).
    sname       :: term(),      %% FSM state name at the end of this transition.
    sdata       :: term(),      %% FSM state data at the end of this transition.
    timestamp   :: timestamp(), %% Start of the transition.
    duration    :: duration(),  %% Duration of the transition (in microseconds).
    trigger_type    :: trigger_type(),                  %% Type of the trigger, initiated the transition.
    trigger_msg     :: msg_ref(),                       %% Message initiated the transition.
    trigger_resp    :: msg_ref() | undefined,           %% Response to the trigger if the event was synchronous.
    trn_messages    :: [msg_ref],                       %% Messages sent and received during transition, not including trigger and its response.
    attr_last_id    :: integer(),                       %% Last action id.
    attr_actions    :: [#attr_action{}],                %% All attribute actions performed in this transition.
    attrs_active    :: [#attribute{}] | undefined,      %% Active props, keys and timers at the target state, Calculated field.
    inst_status     :: inst_status(),                   %% Instance status, after the transition.
    inst_suspend    :: #inst_suspension{} | undefined   %% Filled, if the instance was suspended and its state updated.
}).

%%
%%  Describes single instance of the `eproc_fsm`.
%%
-record(instance, {
    id          :: inst_id(),           %% Unique auto-generated instance identifier.
    group       :: inst_group(),        %% Group the instance belongs to.
    name        :: inst_name(),         %% Initial name - unique user-specified identifier.
    module      :: module(),            %% Callback module implementing the FSM.
    args        :: term(),              %% Arguments, passed when creating the FSM.
    opts        :: proplist(),          %% Options, used by the `eproc_fsm` behaviour (limits, etc).
    init        :: term(),              %% Initial state data, as returned by init/1.
    status      :: inst_status(),       %% Current status if the FSM instance.
    created     :: datetime(),              %% Time, when the instance was created.
    terminated  :: datetime() | undefined,  %% Time, when the instance was terminated.
    archived    :: datetime() | undefined,  %% Time, when the instance was archived.
    transitions :: [#transition{}] | undefined  %% Instance transitions. Calculated field.
}).



