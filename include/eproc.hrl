%/--------------------------------------------------------------------
%| Copyright 2013-2015 Erisata, UAB (Ltd.)
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
-type timestamp()       :: erlang:timestamp().              % {Mega, Secs, Micro}
-type duration()        :: eproc_timer:duration_spec().     % {1, min}, etc.
-type mfargs()          :: {Module :: module(), Function :: atom(), Args :: [term()]}.

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

-type otp_name() ::
    {local, atom()} |
    {global, atom()} |
    {via, module(), term()}.


-type inst_id()         :: eproc_fsm:id().
-type fsm_ref()         :: {inst, InstId :: inst_id()} | {name, Name :: term()}.
-type fsm_key()         :: {key, Key :: term()} | {key, Key :: term(), Opts :: list()}.
-type fsm_start_spec()  :: eproc_fsm:start_spec().
-type inst_app()        :: atom().
-type inst_type()       :: atom().
-type inst_name()       :: term().
-type inst_group()      :: eproc_fsm:group().
-type inst_status()     :: running | suspended | resuming | completed | killed | failed.
-type codec_ref()       :: eproc_codec:ref().
-type store_ref()       :: eproc_store:ref().
-type archive_ref()     :: eproc_archive:ref().
-type registry_ref()    :: eproc_registry:ref().
-type trn_nr()          :: integer().                           %% Starts from 1.
-type trn_id()          :: {inst_id(), trn_nr()}.               %% Unique transition reference.
-type stt_nr()          :: 0 | trn_nr().                        %% Starts from 0 (initial state).
-type stt_id()          :: {inst_id(), stt_nr()}.               %% Unique instance state reference.
-type intr_nr()         :: integer().                           %% Local to particular transition.
-type intr_id()         :: {inst_id(), trn_nr(), intr_nr()}.    %% Unique interrupt id.
-type attr_nr()         :: integer().                           %% Starts from 1, unique in instance.
-type attr_id()         :: {inst_id(), attr_nr()}.              %% Unique attribute id.
-type msg_nr()          :: 0 | 1 | integer().                               %% Message number in transition.
-type msg_id()          :: {inst_id(), trn_nr(), msg_nr()}.                 %% Message Id.
-type msg_cid()         :: {inst_id(), trn_nr(), msg_nr(), (sent | recv)}.  %% Message Copy Id.
-type party()           :: {inst, inst_id()} | {ext, term()}.
-type scope()           :: list().
-type script()          :: [(Call :: mfargs() | {Response :: term(), Call :: mfargs()})].
-type node_ref()        :: atom().

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
%%  Describes action made by a used.
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
    {admin, #user{} | undefined} |
    {Type :: atom(), Id :: term()} |
    undefined.


%%
%%  A reference to a message, that can be attached to a specific
%%  transition.
%%
-record(msg_ref, {
    cid         :: msg_cid(),                   %% ID of the message copy.
    peer        :: event_src(),                 %% Sender or receiver of the message.
    type        :: binary()                     %% User defined type of the message.
}).


%%
%%  A message, that was sent from a sender to a receiver.
%%  At least one of them will be an FSM instance.
%%
-record(message, {
    msg_id      :: msg_cid() | msg_id(),        %% Unique identifier.
    sender      :: event_src(),                 %% Source.
    receiver    :: event_src(),                 %% Destination.
    resp_to     :: msg_cid() | undefined,       %% Indicates a request message, if thats a response to it.
    type        :: binary(),                    %% User defined type of the message.
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
-type trigger_type() :: event | sync | info | timer | self | admin | create | atom().


%%
%%  Trigger initiates FSM transitions. Event (message) is the core
%%  attribute of the trigger. Additionally event source, type and
%%  other attributes are used to define the trigger more preciselly.
%%
%%  Example triggers:
%%
%%      #trigger_spec{type = event, source = {inst, {12364,m}},     message = any,             sync = false},
%%      #trigger_spec{type = event, source = {connector, api},      message = any,             sync = false},
%%      #trigger_spec{type = sync,  source = {connector, api},      message = any,             sync = true},
%%      #trigger_spec{type = timer, source = {attr, 1231221},       message = timeout,         sync = false},
%%      #trigger_spec{type = admin, source = {admin, {user, ...}},  message = "Problem fixed", sync = false}.
%%
%%  This structure is transient, not intended for storing in a DB.
%%
-record(trigger_spec, {
    type            :: trigger_type(),          %% Type of the trigger.
    source          :: event_src(),             %% Party, initiated the trigger, event source, admin name.
    message         :: term(),                  %% Event message / body.
    msg_cid         :: undefined | msg_cid(),   %% Event message id, optional.
    msg_type_fun    :: function(),              %% Function, deriving user defined message type.
    sync = false    :: boolean(),               %% True, if the trigger expects an immediate response.
    reply_fun       :: undefined | function(),  %% Function used to sent response if the trigger is sync.
    src_arg         :: boolean()                %% If set to true, event source will be passed to an FSM implementation.
}).


%%
%%  An attribute is main mechanism for extending FSM behaviour. This structure
%%  define common structure for attributes, that can be attached to FSM for
%%  some period of its lifecycle.
%%
-record(attribute, {
    attr_id     :: attr_nr() | attr_id(),   %% Id of an attribute, unique within FSM instance.
    module      :: module(),                %% Attribute implementation callback module.
    name        :: term() | undefined,      %% Attributes can be named or unnamed.
    scope       :: term(),                  %% Each attribute has its validity scope.
    data        :: term(),                  %% Custom attribute data.
    from        :: trn_nr(),                %% Transition at which the attribute was set.
    upds = []   :: [trn_nr()],              %% Transitions at which the attribute was updated.
    till        :: trn_nr() | undefined,    %% Transition at which the attribute was removed.
    reason      :: term()                   %%  Reason for the attribute removal.
}).


%%
%%  Each transition can create, update or remove attributes.
%%  This structure describes such actions. They are attached to transitions
%%  and can be used to replay them to calculate a list of active attributes
%%  at a specific transition.
%%
-record(attr_action, {
    module      :: module(),
    attr_nr     :: integer(),
    action      ::
        {create, Name :: term(), Scope :: term(), Data :: term()} |
        {update, NewScope :: term(), NewData :: term()} |
        {remove, Reason :: (
            {scope, NewSName :: term()} |
            {user, UserReason :: term()}
        )},
    needs_store = false :: boolean()    % True, if this attribute action should be handled in the store.
}).


%%
%%  Resume attempt of an interrupt.
%%
-record(resume_attempt, {
    res_nr      :: integer(),                   %% Number of the resume attempt.
    upd_sname   :: term() | undefined,          %% FSM state name set by an administrator.
    upd_sdata   :: term() | undefined,          %% FSM state data set by an administrator.
    upd_script  :: script() | undefined,        %% Update script, can be attribute API functions.
    resumed     :: #user_action{}               %% Who, when, why resumed/updated the FSM.
}).


%%
%%  Describes single FSM interrupt with possibly several resume attempts.
%%  An administrator can update the process state and its atributes
%%  when resuming the FSM.
%%
-record(interrupt, {
    intr_id     :: intr_nr() | intr_id() | undefined,   %% Interrupt reference, undefined if active.
    status      :: active | closed,                     %% Interrupt status.
    suspended   :: timestamp(),                         %% When the FSM was suspended.
    reason      :: #user_action{} | {fault, Reason :: term()} | {impl, Reason :: term()},
    resumes     :: [#resume_attempt{}]                  %% Last resume attempt in the head of the list.
}).


%%
%%  Describes single transition of a particular instance.
%%  This structure describes transition and the target state.
%%
-record(transition, {
    trn_id          :: trn_nr() | trn_id(),             %% Transition number in the FSM (starts at 1) or reference.
    sname           :: term(),                          %% FSM state name at the end of this transition.
    sdata           :: term(),                          %% FSM state data at the end of this transition.
    timestamp       :: timestamp(),                     %% Start of the transition.
    duration        :: duration(),                      %% Duration of the transition (in microseconds).
    trn_node        :: node_ref(),                      %% Which node the transition was performed on.
    trigger_type    :: trigger_type(),                  %% Type of the trigger, initiated the transition.
    trigger_msg     :: msg_ref(),                       %% Message initiated the transition.
    trigger_resp    :: msg_ref() | undefined,           %% Response to the trigger if the event was synchronous.
    trn_messages    :: [msg_ref()],                     %% Messages sent and received during transition, not including trigger and its response.
    attr_last_nr    :: attr_nr(),                       %% Last action id.
    attr_actions    :: [#attr_action{}],                %% All attribute actions performed in this transition.
    inst_status     :: inst_status(),                   %% Instance status, after the transition.
    interrupts      :: [#interrupt{}] | undefined       %% Filled, if the instance was suspended at this transition.
}).


%%
%%  Describes particular state of the FSM. If `#transition{}` corresponds to the
%%  transition arrow in the FSM diagram, the `#inst_state{}` stands for the
%%  named state of an object. This state record can be reconstructed from
%%  all the transitions by replaying them on the initial FSM state.
%%
-record(inst_state, {
    stt_id          :: stt_nr() | stt_id(),         %% Identifies a transition by which the state was reached.
    sname           :: term(),                      %% FSM state name.
    sdata           :: term(),                      %% FSM state data.
    timestamp       :: timestamp(),                 %% State entry timestamp.
    attr_last_nr    :: attr_nr(),                   %% Last used FSM attribute ID.
    attrs_active    :: [#attribute{}] | undefined,  %% List of attributes, that are active at this state.
    interrupts      :: [#interrupt{}] | undefined   %% All the interrupts, closed in this state.
}).


%%
%%  Describes single instance of the `eproc_fsm`.
%%
-record(instance, {
    inst_id     :: inst_id(),                           %% Unique auto-generated instance identifier.
    group       :: inst_group(),                        %% Group the instance belongs to.
    type        :: inst_type(),                         %% Type of the process (can differ from the module).
    app         :: inst_app(),                          %% Application to which the instance belongs.
    name        :: inst_name(),                         %% Initial name - unique user-specified identifier.
    module      :: module(),                            %% Callback module implementing the FSM.
    args        :: term(),                              %% Arguments, passed when creating the FSM.
    opts        :: proplist(),                          %% Options, used by the `eproc_fsm` behaviour (limits, etc).
    start_spec  :: fsm_start_spec() | undefined,        %% Optional FSM start specification.
    status      :: inst_status(),                       %% Current status if the FSM instance.
    created     :: timestamp(),                         %% Time, when the instance was created.
    create_node :: node_ref(),                          %% Node at which this instance was created.
    terminated  :: timestamp() | undefined,             %% Time, when the instance was terminated.
    term_reason :: #user_action{} | normal | undefined, %% Reason, why the instance was terminated.
    archived    :: timestamp() | undefined,             %% Time, when the instance was archived.
    interrupt   :: #interrupt{} | undefined,            %% Currently active interrupt.
    curr_state  :: #inst_state{} | undefined,           %% Current state of the instance.       Filled if requested.
    arch_state  :: #inst_state{} | undefined,           %% Oldest known state of the instance.  Filled if requested.
    transitions :: [#transition{}] | undefined          %% Instance transitions till the state. Filled if requested.
}).


