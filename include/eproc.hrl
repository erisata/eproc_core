%/--------------------------------------------------------------------
%| Copyright 2013 Robus, Ltd.
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

-type inst_id()         :: eproc_fsm:id().
-type fsm_ref()         :: {inst, inst_id()} | {name, term()}.  % TODO: Key should not be used in runtime registration: {key, term()}.
-type inst_name()       :: term().
-type inst_group()      :: eproc_fsm:group().
-type inst_status()     :: running | suspended | done | failed | killed.
-type store_ref()       :: eproc_store:ref().
-type registry_ref()    :: eproc_registry:ref().
-type trn_nr()          :: integer().
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

-record(user_action, {
    user    :: #user{},
    time    :: timestamp(),
    comment :: binary()
}).

%%
%%  See `eproc_fsm.erl` for more details.
%%

-record(inst_prop, {
    inst_id :: inst_id(),   %% Id of an instance the property belongs to.
    name    :: binary(),    %% Name of the property.
    value   :: binary(),    %% Value of the property.
    from    :: trn_nr()     %% Transition at which the property was set.
}).

-record(inst_key, {
    inst_id :: inst_id(),   %% Id of an instance the key belongs to.
    value   :: term(),      %% Value of the key.
    scope   :: scope(),     %% Scope, in which the key is valid.
    from    :: trn_nr(),                %% Transition at which the key was set.
    till    :: trn_nr() | undefined,    %% Transition at which the key was removed.
    reason  :: (scope | cancel | admin) %% Reason for the key removal.
}).

-record(inst_timer, {
    inst_id     :: inst_id(),   %% Id of an instance the timer belongs to.
    name        :: term(),      %% Name of the timer.
    start       :: timestamp(), %% Time at which the timer was set.
    duration    :: integer(),   %% Duration of the timer in miliseconds.
    message     :: term(),      %% Message to be sent to the FSM when the timer fires.
    scope       :: scope(),     %% Scope in which the key is valid.
    from        :: trn_nr(),                        %% Transition at which the timer was set.
    till        :: trn_nr() | undefined,            %% Transition at which the timer was removed.
    reason      :: (fired | scope | cancel | admin) %% Reason for the timer removal.
}).

-type inst_attr() ::
    #inst_prop{} |
    #inst_key{} |
    #inst_timer{}.

-type trigger() ::
    {event, Src :: party(), Message :: term()} |
    {sync,  Src :: party(), Request :: term(), Response :: term()} |
    {timer, Name :: term(), Message :: term()} |
    {admin, Reason :: term()}.

-type effect() ::
    {event, Dst :: party(), Message :: term()} |                        %% Async message sent.
    {sync,  Dst :: party(), Request :: term(), Response :: term()} |    %% Synchronous message sent.
    {name,  Name :: term()} |                                           %% New name set.
    {prop,  PropName :: term(), PropValue :: term()} |                  %% New property set / existing replaced.
    {key,   KeyValue :: term(), Scope :: term()} |                      %% New key added.
    {key,   KeyValue :: term(), Reason :: (scope | cancel | admin)} |   %% Key removed.
    {timer, TimerName :: term(), After :: integer(), Message :: term(), Scope :: term()} |  %% Timer added.
    {timer, TimerName :: term(), Reason :: (fired | scope | cancel | admin)}.               %% Timer removed.



%%
%%  TODO
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
%%  TODO
%%
-record(attr_action, {
    module,
    attr_id,
    action  ::
        {create, Name :: term(), Scope :: term(), Data :: term()} |
        {update, Name :: term(), NewScope :: term(), NewData :: term()} |
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
%%  If resume is failing due to updated data or effects, the process
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
    upd_effects :: [effect()] | undefined,      %% Effects made in this transition.
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
    trigger     :: trigger(),   %% Event, initiated the transition.
    effects     :: [effect()],  %% Effects made in this transition. TODO: Remove?
    attr_id     :: integer(),                           %% Last action id.
    attr_actions    :: [#attr_action{}],                %% All attribute actions performed in this transition.
    attrs_active    :: [inst_attr()] | undefined,       %% Active props, keys and timers at the target state, Calculated field.
    suspensions     :: #inst_suspension{} | undefined   %% Filled, if the instance was suspended and its state updated.
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



