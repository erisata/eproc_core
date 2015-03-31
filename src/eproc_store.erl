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
%%  Main interface for a store implementation. The core engine is always using
%%  this module to access the database. Several implementations of this interface
%%  are provided. The `eproc_core` provides ETS and Mnesia based implementations.
%%  Riak based implementation is provided by the `eproc_riak` component.
%%
%%  TODO: A lot of functionality is duplicated between store implementations. This behaviour should be reviewed.
%%
-module(eproc_store).
-compile([{parse_transform, lager_transform}]).
-export([
    ref/0, ref/2,
    supervisor_child_specs/1,
    get_instance/3,
    get_transition/4,
    get_state/4,
    get_message/3,
    get_node/1
]).
-export([
    add_instance/2,
    add_transition/4,
    set_instance_killed/3,
    set_instance_suspended/3,
    set_instance_resuming/4,
    set_instance_resumed/3,
    load_instance/2,
    load_running/2,
    attr_task/3
]).
-export([
    is_instance_terminated/1,
    apply_transition/3,
    make_resume_attempt/3,
    determine_transition_action/2,
    instance_age_us/2,
    instance_last_trn_time/1,
    instance_sort/2,
    sublist_opt/3,
    member_in_all/2
]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  This callback should return a list of supervisor child specifications
%%  used to start the store.
%%
-callback supervisor_child_specs(
        StoreArgs   :: term()
    ) ->
        {ok, list()}.


%%
%%  This function should register new persistent FSM.
%%  Additionally, the following should be performed:
%%
%%    * Unique FSM InstId should be generated.
%%    * Unique group should be generated, if group=new.
%%    * Fill instance id in related structures.
%%
-callback add_instance(
        StoreArgs   :: term(),
        Instance    :: #instance{}
    ) ->
        {ok, inst_id()}.


%%
%%  This function should register new transition for the FSM.
%%  Additionally, the following should be done:
%%
%%    * Add all related messages.
%%    * Terminate FSM, if the `inst_state` is substate of the `terminated` state.
%%    * suspend FSM, if `inst_state = suspended` and `interrupt = #interrupt{reason = R}`.
%%    * resume FSM, if instance state was `resuming` and new `inst_state = running`.
%%    * Handle attribute actions.
%%
%%  NOTE: For some of messages, a destination instance id will be unknown.
%%  These partially resolved destinations are in form of `{inst, undefined}`
%%  and are stored in messages and transition message references.
%%  A store implementation needs to resolve these message destinations
%%  after the message is stored, for example on first read (or each read).
%%
-callback add_transition(
        StoreArgs   :: term(),
        InstId      :: inst_id(),
        Transition  :: #transition{},
        Messages    :: [#message{}]
    ) ->
        {ok, inst_id(), trn_nr()}.


%%
%%  Mark instance as killed.
%%
-callback set_instance_killed(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        UserAction  :: #user_action{}
    ) ->
        {ok, inst_id()}.


%%
%%  Mark instance as suspended and initialize corresponing interrupt.
%%
-callback set_instance_suspended(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        Reason      :: #user_action{} | {fault, Reason :: term()} | {impl, Reason :: term()}
    ) ->
        {ok, inst_id()}.


%%
%%  This function is invoked when an attempt to resume the FSM made.
%%  It should check if the current status of the FSM is `suspended`
%%  or `resuming`. In other cases it should exit with an error.
%%  The following cases shoud be handled here:
%%
%%   1. Change `#instance.status` from `suspended` to `resuming`.
%%   2. Add the resume attempt to the active interrupt.
%%
-callback set_instance_resuming(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        StateAction :: unchanged | retry_last | {set, NewStateName, NewStateData, ResumeScript},
        UserAction  :: #user_action{}
    ) ->
        {ok, inst_id(), fsm_start_spec()} |
        {error, not_found | running | terminated} |
        {error, Reason :: term()}
    when
        NewStateName :: term() | undefined,
        NewStateData :: term() | undefined,
        ResumeScript :: script() | undefined.


%%
%%  This function transfers the FSM from the `resuming` state to `running`.
%%  The following steps should be done for that:
%%
%%   1. Change `#instance.status` from `resuming` to `running`.
%%   2. Set transition number for the active interrupt number.
%%   3. The active interrupt should be marked as closed.
%%
-callback set_instance_resumed(
        StoreArgs   :: term(),
        InstId      :: inst_id(),
        TrnNr       :: trn_nr()
    ) ->
        ok |
        {error, Reason :: term()}.


%%
%%  Get instance with its current state and active interrupt.
%%
-callback load_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref()
    ) ->
        {ok, #instance{}} |
        {error, not_found}.


%%
%%  Return all FSMs, that should be started automatically on startup.
%%
-callback load_running(
        StoreArgs       :: term(),
        PartitionPred   :: fun((inst_id(), inst_group()) -> boolean())
    ) ->
        {ok, [{FsmRef :: fsm_ref(), StartSpec :: fsm_start_spec()}]}.


%%
%%  Perform attribute action.
%%
-callback attr_task(
        StoreArgs       :: term(),
        AttrModule      :: module(),
        AttrTask        :: term()
    ) ->
        Response :: term().


%%
%%  Get instance data by FSM reference (id or name), list of references or a filter.
%%
%%  In the case of single reference (`FsmRef = fsm_ref()`), this function returns
%%  `{ok, #instance{}}` or `{error, not_found}` if the specified instance was not found.
%%
%%  In the case of a list of references (`FsmRef = {list, [fsm_ref()]}`), this
%%  function returns `{ok, [#instance{}]}`, where order of instances corresponds
%%  to the order of supplied FSM references. This function returns `{error, not_found}`
%%  if any of the requested instances were not found.
%%
%%  In the case of a filtering (`FsmRef = {filter, Paging, [FilterClause]}`), this
%%  function returns `{ok, {TotalCount, TotalExact, [#instance{}]}}`, where `TotalCount`
%%  is a number of known rows, matching the specified filter.
%%  This number should be considered exact, if `TotalExact=true`.
%%  More than `TotalCount` of instances can exist if `TotalExact=false`.
%%  The returned result is an intersection (`AND`) of all filter clauses.
%%  The result will have union (`OR`) of all filter values, specified in a single filter clause.
%%
%%  When performing filtering of the instances, result paging is supported including row sorting.
%%  The defaut sorting is by `last_trn`.
%%
%%  The parameter Query can have several values:
%%
%%  `header`
%%  :   Only main instance data is returned.
%%  `current`
%%  :   Returns FSM header information with the current state attached.
%%  `recent`
%%  :   Returns FSM header information with some recent state attached.
%%      The recent state can be retrieved easier, although can be suitable
%%      in some cases, like showing a list of instances with current state names.
%%
-callback get_instance(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref() | {list, [fsm_ref()]} | {filter, Paging, [FilterClause]},
        Query       :: header | current | recent
    ) ->
        {ok, #instance{} | [#instance{}] | {TotalCount, TotalExact, [#instance{}]}} |
        {error, not_found} |
        {error, Reason :: term()}
    when
        FilterClause ::
            %% TODO: Faulty (see webapi).
            {id,        IIdFilter | [IIdFilter]} | % At most one in Filter list
            {name,      INmFilter | [INmFilter]} | % At most one in Filter list
            {last_trn,  From :: timestamp() | undefined, Till :: timestamp() | undefined} |
            {created,   From :: timestamp() | undefined, Till :: timestamp() | undefined} |
            {tag,       TagFilter | [TagFilter]} |
            {module,    ModFilter | [ModFilter]} |
            {status,    StsFilter | [StsFilter]} |
            {age,       Age :: duration()},  % Older than Age. Instance age = terminated - created, if terminated is undefined, age = now() - created.
        IIdFilter :: InstId :: inst_id(),
        INmFilter :: Name :: inst_name(),
        TagFilter :: TagName :: binary() | {TagName :: binary(), TagType :: binary() | undefined},
        ModFilter :: Module :: module(),
        StsFilter :: Status :: inst_status(),
        Paging    :: {ResFrom, ResCount} | {ResFrom, ResCount, SortedBy}, % SortedBy=last_trn by default
        ResFrom   :: integer() | undefined,
        ResCount  :: integer() | undefined,
        SortedBy  :: id | name | last_trn | created | module | status | age,
        TotalCount :: integer() | undefined,
        TotalExact :: boolean().


%%
%%  Get particular FSM transition.
%%  Any partial message destinations should be resolved when returing message references.
%%
-callback get_transition(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        TrnNr       :: trn_nr() | {list, From :: (trn_nr() | current), Count :: integer()},
        Query       :: all
    ) ->
        {ok, #transition{}} |
        {ok, [#transition{}]} |
        {error, Reason :: term()}.


%%
%%  Get particular FSM state (or a list of them).
%%
-callback get_state(
        StoreArgs   :: term(),
        FsmRef      :: fsm_ref(),
        SttNr       :: stt_nr() | current | {list, From :: (stt_nr() | current), Count :: integer()},
        Query       :: all
    ) ->
        {ok, #inst_state{}} |
        {ok, [#inst_state{}]} |
        {error, Reason :: term()}.


%%
%%  Get particular message by message id, message copy id, list of them of by filter.
%%  The returned message should contain message id instead of message copy id.
%%  Partial message destination should be resolved when returing the message.
%%
%%  Filtering and query by list is similar to get_instance/3 callback. The default
%%  sorting is by date.
%%
-callback get_message(
        StoreArgs   :: term(),
        MsgId       :: msg_id() | msg_cid() | {list, [msg_id() | msg_cid()]} | {filter, Paging, [FilterClause]},
        Query       :: all
    ) ->
        {ok, #message{} | [#message{}] | {TotalCount, TotalExact, [#message{}]}} |
        {error, Reason :: term()}
    when
        FilterClause ::
            {id,        MIdFilter | [MIdFilter]} |
            {date,      From :: timestamp() | undefined, Till :: timestamp() | undefined} |
            {peer,      [PeerFilter]},
        MIdFilter   :: InstId :: inst_id(),
        PeerFilter  :: {Role :: (send | recv | any), event_src()},
        Paging      :: {ResFrom, ResCount} | {ResFrom, ResCount, SortedBy}, % SortedBy=last_trn by default
        ResFrom     :: integer() | undefined,
        ResCount    :: integer() | undefined,
        SortedBy    :: date | sender | receiver,
        TotalCount  :: integer() | undefined,
        TotalExact  :: boolean().


%%
%%  Returns a reference to the current node.
%%
-callback get_node(
        StoreArgs   :: term()
    ) ->
        {ok, node_ref()} |
        {error, Reason :: term()}.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Returns supervisor child specifications, that should be used to
%%  start the store.
%%
-spec supervisor_child_specs(Store :: store_ref()) -> {ok, list()}.

supervisor_child_specs(Store) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:supervisor_child_specs(StoreArgs).


%%
%%  Returns the default store reference.
%%
-spec ref() -> {ok, store_ref()}.

ref() ->
    {ok, {Module, Function, Args}} = eproc_core_app:store_cfg(),
    erlang:apply(Module, Function, Args).



%%
%%  Create a store reference.
%%
-spec ref(module(), term()) -> {ok, store_ref()}.

ref(Module, Args) ->
    {ok, {Module, Args}}.


%%
%%  This function returns an instance, possibly at some state.
%%  If instance not found or other error returns {error, Reason}.
%%
get_instance(Store, FsmRef, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_instance(StoreArgs, FsmRef, Query).


%%
%%  This function returns a transition of the specified FSM.
%%
get_transition(Store, FsmRef, TrnNr, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_transition(StoreArgs, FsmRef, TrnNr, Query).


%%
%%  Get particular FSM state (or a list of them).
%%
get_state(Store, FsmRef, SttNr, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_state(StoreArgs, FsmRef, SttNr, Query).


%%
%%  This function returns a message by message id or message copy id.
%%
get_message(Store, MsgId, Query) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_message(StoreArgs, MsgId, Query).


%%
%%  Returns a reference to the current node.
%%
get_node(Store) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:get_node(StoreArgs).



%% =============================================================================
%%  Functions for `eproc_fsm` and related modules.
%% =============================================================================

%%
%%  Stores new persistent instance, generates id for it,
%%  assigns a group and a name if not provided.
%%  Initial state should be provided in the `#instance.state` field.
%%
add_instance(Store, Instance = #instance{curr_state = #inst_state{}}) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:add_instance(StoreArgs, Instance).


%%
%%  Add a transition for existing FSM instance.
%%  Messages received or sent during the transition are also saved.
%%  Instance state is updated according to data in the transition.
%%
add_transition(Store, InstId, Transition, Messages) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:add_transition(StoreArgs, InstId, Transition, Messages).


%%
%%  Marks an FSM instance as killed.
%%
set_instance_killed(Store, FsmRef, UserAction) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_killed(StoreArgs, FsmRef, UserAction).


%%
%%  Marks an FSM instance as suspended.
%%
set_instance_suspended(Store, FsmRef, Reason) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_suspended(StoreArgs, FsmRef, Reason).


%%
%%  Marks an FSM as resuming after it was suspended.
%%
set_instance_resuming(Store, FsmRef, StateAction, UserAction) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_resuming(StoreArgs, FsmRef, StateAction, UserAction).


%%
%%  Marks an FSM as running after it was suspended.
%%  This function is called from the running FSM process.
%%
set_instance_resumed(Store, InstId, TrnNr) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:set_instance_resumed(StoreArgs, InstId, TrnNr).


%%
%%  Loads an instance and its current state.
%%  This function returns an instance with latest state.
%%
load_instance(Store, FsmRef) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_instance(StoreArgs, FsmRef).



%%
%%  Load all running FSMs. This function is used by a registry to get
%%  all FSMs to be restarted. Predicate PartitionPred can be used to
%%  filter FSMs.
%%
load_running(Store, PartitionPred) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:load_running(StoreArgs, PartitionPred).


%%
%%  Perform attribute task. User for performing
%%  data queries and synchronous actions.
%%
attr_task(Store, AttrModule, AttrTask) ->
    {ok, {StoreMod, StoreArgs}} = resolve_ref(Store),
    StoreMod:attr_task(StoreArgs, AttrModule, AttrTask).



%% =============================================================================
%%  Functions for `eproc_store` implementations.
%% =============================================================================

%%
%%  Checks if instance is terminated by status.
%%
is_instance_terminated(running)   -> false;
is_instance_terminated(suspended) -> false;
is_instance_terminated(resuming)  -> false;
is_instance_terminated(completed) -> true;
is_instance_terminated(failed)    -> true;
is_instance_terminated(killed)    -> true.


%%
%%  Replay transition on a specified state.
%%  State and transition should have unqualified identifiers (`trn_nr()` and `stt_nr()`).
%%
apply_transition(Transition, InstState, InstId) ->
    #inst_state{
        stt_id = SttNr,
        attrs_active = Attrs
    } = InstState,
    #transition{
        trn_id = TrnId,
        sname = SName,
        sdata = SData,
        timestamp = Timestamp,
        attr_last_nr = AttrLastNr,
        attr_actions = AttrActions
    } = Transition,
    TrnNr = case TrnId of
        {_IID, T} -> T;
        _         -> TrnId
    end,
    TrnNr = SttNr + 1,
    {ok, NewAttrs} = eproc_fsm_attr:apply_actions(AttrActions, Attrs, InstId, TrnNr),
    InstState#inst_state{
        stt_id = TrnNr,
        sname = SName,
        sdata = SData,
        timestamp = Timestamp,
        attr_last_nr = AttrLastNr,
        attrs_active = NewAttrs
    }.


%%
%%  Creates resume attempt based on user input.
%%
make_resume_attempt(StateAction, UserAction, Resumes) ->
    LastResNumber = case Resumes of
        [] -> 0;
        [#resume_attempt{res_nr = N} | _] -> N
    end,
    case StateAction of
        unchanged ->
            #resume_attempt{
                res_nr = LastResNumber + 1,
                upd_sname = undefined,
                upd_sdata = undefined,
                upd_script = undefined,
                resumed = UserAction
            };
        retry_last ->
            case Resumes of
                [] ->
                    #resume_attempt{
                        res_nr = LastResNumber + 1,
                        upd_sname = undefined,
                        upd_sdata = undefined,
                        upd_script = undefined,
                        resumed = UserAction
                    };
                [#resume_attempt{upd_sname = LastSName, upd_sdata = LastSData, upd_script = LastScript} | _] ->
                    #resume_attempt{
                        res_nr = LastResNumber + 1,
                        upd_sname = LastSName,
                        upd_sdata = LastSData,
                        upd_script = LastScript,
                        resumed = UserAction
                    }
            end;
        {set, NewStateName, NewStateData, ResumeScript} ->
            #resume_attempt{
                res_nr = LastResNumber + 1,
                upd_sname = NewStateName,
                upd_sdata = NewStateData,
                upd_script = ResumeScript,
                resumed = UserAction
            }
    end.


%%
%%  Determines transition action.
%%
determine_transition_action(Transition = #transition{inst_status = Status}, OldStatus) ->
    OldTerminated = is_instance_terminated(OldStatus),
    NewTerminated = is_instance_terminated(Status),
    case {OldTerminated, NewTerminated, OldStatus, Transition} of
        {false, false, suspended, #transition{inst_status = running, interrupts = undefined}} ->
            none;
        {false, false, running, #transition{inst_status = running, interrupts = undefined}} ->
            none;
        {false, false, running, #transition{inst_status = suspended, interrupts = [Interrupt]}} ->
            #interrupt{reason = Reason} = Interrupt,
            {suspend, Reason};
        {false, false, resuming, #transition{inst_status = running, interrupts = undefined}} ->
            resume;
        {false, true, _, #transition{interrupts = undefined}} ->
            terminate;
        {true, _, _, _} ->
            {error, terminated}
    end.


%%
%%  Returns the age of the instance in microseconds.
%%  The current time can be passed as the second parameter to simulate
%%  the age calculation of several instances at the same time.
%%
-spec instance_age_us(#instance{}, os:timestamp()) -> integer().

instance_age_us(#instance{created = Created, terminated = undefined}, Now) ->
    eproc_timer:timestamp_diff_us(Now, Created);

instance_age_us(#instance{created = Created, terminated = Terminated}, _) ->
    eproc_timer:timestamp_diff_us(Terminated, Created).


%%
%%  Returns last transition timestamp() of the instance or undefined,
%%  it is not available.
%%
-spec instance_last_trn_time(#instance{}) -> os:timestamp() | undefined.

instance_last_trn_time(#instance{curr_state = undefined})                           -> undefined;
instance_last_trn_time(#instance{curr_state = #inst_state{stt_id = 0}})             -> undefined;
instance_last_trn_time(#instance{curr_state = #inst_state{timestamp = Timestamp}})  -> Timestamp.


%%
%%  Sort instances by specified criteria.
%%
-spec instance_sort([#instance{}], SortBy) -> [#instance{}]
    when SortBy :: id | name | last_trn | created | module | status | age.

instance_sort(Instances, SortBy) ->
    SortFun = case SortBy of
        id ->
            fun(#instance{inst_id = ID1}, #instance{inst_id = ID2}) ->
                ID1 =< ID2
            end;
        name ->
            fun(#instance{name = Name1}, #instance{name = Name2}) ->
                Name1 =< Name2
            end;
        last_trn ->
            fun(#instance{} = Instance1, #instance{} = Instance2) ->
                instance_last_trn_time(Instance1) >= instance_last_trn_time(Instance2)
            end;
        created ->
            fun(#instance{created = Cr1}, #instance{created = Cr2}) ->
                Cr1 >= Cr2
            end;
        module ->
            fun(#instance{module = Module1}, #instance{module = Module2}) ->
                Module1 =< Module2
            end;
        status ->
            fun(#instance{status = Status1}, #instance{status = Status2}) ->
                Status1 =< Status2
            end;
        age ->
            Now = os:timestamp(),
            fun(#instance{} = Instance1, #instance{} = Instance2) ->
                instance_age_us(Instance1, Now) >= instance_age_us(Instance2, Now)
            end
    end,
    lists:sort(SortFun, Instances).


%%
%%  sublist_opt(L, F, C) returns C elements of list L starting with F-th element of the list.
%%  L should be list, F - positive integer, C positive integer or 0.
%%
sublist_opt(List, From, _Count) when From > erlang:length(List) ->
    [];

sublist_opt(List, From, Count) ->
    lists:sublist(List, From, Count).


%%
%%  Checks, if all lists contain the specified element.
%%
member_in_all(_Element, []) ->
    true;

member_in_all(Element, [List | Other]) ->
    case lists:member(Element, List) of
        false -> false;
        true -> member_in_all(Element, Other)
    end.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Resolve the provided (optional) store reference.
%%
resolve_ref({StoreMod, StoreArgs}) ->
    {ok, {StoreMod, StoreArgs}};

resolve_ref(undefined) ->
    ref().


