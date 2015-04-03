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
    intersect_filter_values/1,
    group_filter_by_type/2,
    general_filter_to_ms/5
]).
-export([
    instance_age_us/2,
    instance_last_trn_time/1,
    instance_sort/2,
    instance_filter_to_ms/2
]).
-export([
    normalise_message_id/1,
    normalise_message/1,
    normalise_message_id_filter/1,
    message_sort/2,
    message_filter_to_ms/2
]).
-export([
    sublist_opt/3,
    make_list/1,
    member_in_all/2,
    intersect_lists/1
]).
-export_type([ref/0]).
-include("eproc.hrl").

-opaque ref() :: {Callback :: module(), Args :: term()}.

-define(INST_MSVAR_ID, '$1').
-define(INST_MSVAR_NAME, '$2').
-define(INST_MSVAR_MODULE, '$3').
-define(INST_MSVAR_STATUS, '$4').
-define(INST_MSVAR_CREATED, '$5').
-define(INST_MSVAR_CURR_STATE, '$6').
-define(INST_MSVAR_TERMINATED, '$7').

-define(MSG_MSVAR_ID, '$1').
-define(MSG_MSVAR_SENDER, '$2').
-define(MSG_MSVAR_RECEIVER, '$3').
-define(MSG_MSVAR_DATE, '$5').


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
        %    {inst_id,   IIdFilter | [IIdFilter]} | %% TODO?
            {date,      From :: timestamp() | undefined, Till :: timestamp() | undefined} |
            {peer,      PeerFilter | [PeerFilter]},
        MIdFilter   :: msg_id() | msg_cid() ,
        %IIdFilter   :: InstId :: inst_id(),
        PeerFilter  :: {Role :: (send | recv | any), event_src()},
        Paging      :: {ResFrom, ResCount} | {ResFrom, ResCount, SortedBy}, % SortedBy=date by default
        ResFrom     :: integer() | undefined,
        ResCount    :: integer() | undefined,
        SortedBy    :: id | date | sender | receiver,
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
%%  Returns intersection of several clauses (of the same type).
%%
-spec intersect_filter_values([{atom(), term() | [term()]}]) -> [term()].

intersect_filter_values(Clauses) ->
    ListOfValueLists = [ make_list(ValueOrList) || {_ClauseType, ValueOrList} <- Clauses ],
    intersect_lists(ListOfValueLists).


%%
%%  Collects and groups filter clauses of specified types.
%%  It is assumed that filter is a tuple, and its first element is atom, which is filter type.
%%  The function also returns all other (not grouped) instance filter clauses.
%%
-spec group_filter_by_type(list(), [atom()]) -> {ok, [[term()]], [term()]}.

group_filter_by_type(Filters, GroupTypes) ->
    GroupFun = fun (FilterClause, {Groups, Other}) ->
        FilterName = erlang:element(1, FilterClause),
        case lists:keyfind(FilterName, 1, Groups) of
            {FilterName, GroupClauses} ->
                NewGroupClauses = [FilterClause | GroupClauses],
                NewGroups = lists:keyreplace(FilterName, 1, Groups, {FilterName, NewGroupClauses}),
                {NewGroups, Other};
            false ->
                {Groups, [FilterClause | Other]}
        end
    end,
    GroupedInitial = [ {T, []} || T <- GroupTypes ],
    {Grouped, Other} = lists:foldl(GroupFun, {GroupedInitial, []}, Filters),
    {ok, [ Clauses || {_, Clauses} <- Grouped ], Other}.


%%
%%  This function takes a list of filter clauses (`Filters`) and converts it
%%  to a match specification. The `SkipFilters` parameter can be used to
%%  ignore clauses of some types, when creating the match specification. This
%%  function can produce match specification for different objects as defined
%%  by parameters:
%%      `MatchHead` - head part of match specification,
%%      `FilterToGuardFun` - function, which takes a single filter clause and
%%      returns a list of filter guard expressions for that clause.
%%      `MatchBody` - body part of match specification.
%%
-spec general_filter_to_ms(Filters, SkipFilters, MatchHead, FilterToGuardFun, MatchBody) -> {ok, ets:match_spec()}
    when
        Filters :: list(Filter),
        Filter :: tuple(),
        SkipFilters :: [atom()],
        MatchHead :: term(),
        FilterToGuardFun :: fun((Filter) -> list(tuple())),
        MatchBody :: list().

general_filter_to_ms(Filters, SkipFilters, MatchHead, FilterToGuardFun, MatchBody) ->
    MakeGuardFun = fun(FilterClause, Guards) ->
        FilterName = erlang:element(1, FilterClause),
        case lists:member(FilterName, SkipFilters) of
            true ->
                Guards;
            false ->
                ClauseGuards = FilterToGuardFun(FilterClause),
                [ClauseGuards | Guards]
        end
    end,
    Guards = lists:foldr(MakeGuardFun, [], Filters),
    MatchFunction = {MatchHead, lists:flatten(Guards), MatchBody},
    MatchSpec = [MatchFunction],
    {ok, MatchSpec}.


%%
%%  Makes OR guards, if multiple guard expressions are supplied.
%%  If some OR guards are supplied in the list, unpacks their condition expressions.
%%
make_orelse_guard([], _MakeGuardFun) ->
    [];

make_orelse_guard([Value], MakeGuardFun) ->
    [MakeGuardFun(Value)];

make_orelse_guard(Values, MakeGuardFun) when is_list(Values)->
    MakeGuardOptimisedFun = fun(Filter) ->
        Guard = MakeGuardFun(Filter),
        GuardType = erlang:element(1, Guard),
        case GuardType of
            'orelse' ->
                ['orelse' | Conditions] = erlang:tuple_to_list(Guard),
                Conditions;
            _ ->
                Guard
        end
    end,
    GuardList = lists:map(MakeGuardOptimisedFun, Values),
    [erlang:list_to_tuple(['orelse' | lists:flatten(GuardList)])].


%% =============================================================================
%%  Instance related functions for `eproc_store` implementations
%% =============================================================================

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
%%  This function takes a list of instance filter clauses and converts it
%%  to a match specification for `#instance{}` records. This function also
%%  normalizes age clause to improve performance. The `SkipFilters`
%%  parameter can be used to ignore clauses of some types, when creating
%%  the match specification.
%%
-spec instance_filter_to_ms(list(), [atom()]) -> {ok, ets:match_spec()}.

instance_filter_to_ms(InstanceFilters, SkipFilters) ->
    %
    % Normalize filter clauses (group ages).
    {ok, AgeClauses, OtherClauses} = group_filter_by_type(InstanceFilters, [age]),
    NormalizedFilters = case AgeClauses of
        [] ->
            InstanceFilters;
        [_SingleAgeClause] ->
            InstanceFilters;
        _MultipleAgeClauses ->
            AgesMS = [ eproc_timer:duration_to_ms(Age) || {age, Age} <- AgeClauses ],
            [{age, {lists:max(AgesMS), ms}} | OtherClauses]
    end,
    GoodSkipFilters = case lists:member(tag, SkipFilters) of
        true -> SkipFilters;
        false -> [tag | SkipFilters]
    end,
    MatchHead = #instance{
        inst_id = ?INST_MSVAR_ID,
        name = ?INST_MSVAR_NAME,
        module = ?INST_MSVAR_MODULE,
        status = ?INST_MSVAR_STATUS,
        created = ?INST_MSVAR_CREATED,
        curr_state = ?INST_MSVAR_CURR_STATE,
        terminated = ?INST_MSVAR_TERMINATED,
        _ = '_'
    },
    MatchBody = ['$_'],
    general_filter_to_ms(NormalizedFilters, GoodSkipFilters, MatchHead, fun instance_filter_to_guard/1, MatchBody).


%%
%% Takes instance filter clause as a parameter and returns a list of its
%% corresponding match condition (guard) expressions for match specification.
%% If no guard should be returned, returns [].
%%
instance_filter_to_guard({id, InstIdOrList}) ->
    MakeGuardFun = fun (InstId) ->
        {'==', ?INST_MSVAR_ID, {const, InstId}}
    end,
    make_orelse_guard(make_list(InstIdOrList), MakeGuardFun);

instance_filter_to_guard({name, NameOrList}) ->
    MakeGuardFun = fun (Name) ->
        {'==', ?INST_MSVAR_NAME, {const, Name}}
    end,
    make_orelse_guard(make_list(NameOrList), MakeGuardFun);

instance_filter_to_guard({last_trn, undefined, undefined}) ->
    [];

instance_filter_to_guard({last_trn, From, undefined}) ->
    [
        {'>=',  {element, #inst_state.timestamp, ?INST_MSVAR_CURR_STATE}, {const, From}},
        {'=/=', {element, #inst_state.stt_id,    ?INST_MSVAR_CURR_STATE}, {const, 0}}
    ];

instance_filter_to_guard({last_trn, undefined, Till}) ->
    [
        {'=<', {element, #inst_state.timestamp, ?INST_MSVAR_CURR_STATE}, {const, Till}}
    ];

instance_filter_to_guard({last_trn, From, Till}) ->
    [
        instance_filter_to_guard({last_trn, From, undefined}),
        instance_filter_to_guard({last_trn, undefined, Till})
    ];

instance_filter_to_guard({created, undefined, undefined}) ->
    [];

instance_filter_to_guard({created, From, undefined}) ->
    [
        {'>=', ?INST_MSVAR_CREATED, {const, From}}
    ];

instance_filter_to_guard({created, undefined, Till}) ->
    [
        {'=<', ?INST_MSVAR_CREATED, {const, Till}}
    ];

instance_filter_to_guard({created, From, Till}) ->
    [
        instance_filter_to_guard({created, From, undefined}),
        instance_filter_to_guard({created, undefined, Till})
    ];

instance_filter_to_guard({tag, Tags}) ->
    erlang:error(tags_guard_not_supported_in_matchspec, Tags);

instance_filter_to_guard({module, ModuleOrList}) ->
    MakeGuardFun = fun (Module) ->
        {'==', ?INST_MSVAR_MODULE, {const, Module}}
    end,
    make_orelse_guard(make_list(ModuleOrList), MakeGuardFun);

instance_filter_to_guard({status, StatusOrList}) ->
    MakeGuardFun = fun (Status) ->
        {'==', ?INST_MSVAR_STATUS, {const, Status}}
    end,
    make_orelse_guard(make_list(StatusOrList), MakeGuardFun);

instance_filter_to_guard({age, MinAge}) ->
    Now = os:timestamp(),
    NowUS = eproc_timer:timestamp_diff_us(Now, {0, 0, 0}),
    MinAgeUS = eproc_timer:duration_to_ms(MinAge) * 1000,
    %
    % This part mirrors parts of  'eproc_timer:timestamp_diff_us/2' and
    % represents expression `T1 = (T1M * ?MEGA + T1S) * ?MEGA + T1U`.
    TimestampUS = fun (VarRef) ->
        {'+',
            {'*',
                {'+',
                    {'*',
                        {element, 1, VarRef},
                        1000000
                    },
                    {element, 2, VarRef}
                },
                1000000
            },
            {element, 3, VarRef}
        }
    end,
    TStampDiffUS = fun (Date2US, Date1US) ->
        {'-', Date2US, Date1US}
    end,
    %
    % This part mirrors contents of `eproc_store:instance_age_us/2`.
    Guard = {'orelse',
        {'andalso',
            {'=:=', {const, undefined}, ?INST_MSVAR_TERMINATED},
            {'=<', {const, MinAgeUS}, TStampDiffUS({const, NowUS}, TimestampUS(?INST_MSVAR_CREATED))}
        },
        {'=<', {const, MinAgeUS}, TStampDiffUS(TimestampUS(?INST_MSVAR_TERMINATED), TimestampUS(?INST_MSVAR_CREATED))}
    },
    [Guard].


%% =============================================================================
%%  Message related functions for `eproc_store` implementations
%% =============================================================================

%%
%% Makes message id out of message id or message copy id.
%%
-spec normalise_message_id(msg_id() | msg_cid()) -> msg_id().

normalise_message_id({InstId, TrnNr, MsgNr, sent})  -> {InstId, TrnNr, MsgNr};
normalise_message_id({InstId, TrnNr, MsgNr, recv})  -> {InstId, TrnNr, MsgNr};
normalise_message_id({InstId, TrnNr, MsgNr})        -> {InstId, TrnNr, MsgNr}.


%%
%% Replaces message id or message copy id by message id in #message{} record.
%%
normalise_message(Message = #message{msg_id = MsgId}) ->
    Message#message{msg_id = normalise_message_id(MsgId)}.


%%
%% Replaces message id or message copy id by message id in a single message
%% filter clause.
%%
normalise_message_id_filter({id, Values}) when is_list(Values) ->
    {id, lists:map(fun normalise_message_id/1, Values)};

normalise_message_id_filter({id, SingleValue}) ->
    {id, normalise_message_id(SingleValue)}.


%%
%%  Sort messages by specified criteria.
%%
-spec message_sort([#message{}], SortBy) -> [#message{}]
    when SortBy :: id | date | sender | receiver.

message_sort(Messages, SortBy) ->
    SortFun = case SortBy of
        id ->
            fun(#message{msg_id = ID1}, #message{msg_id = ID2}) ->
                ID1 =< ID2
            end;
        date ->
            fun(#message{date = Date1}, #message{date = Date2}) ->
                Date1 >= Date2
            end;
        sender ->
            fun(#message{sender = Sender1}, #message{sender = Sender2}) ->
                Sender1 =< Sender2
            end;
        receiver ->
            fun(#message{receiver = Receiver1}, #message{receiver = Receiver2}) ->
                Receiver1 =< Receiver2
            end
    end,
    lists:sort(SortFun, Messages).


%%
%%  This function takes a list of message filter clauses and converts it
%%  to a match specification for `#message{}` records. The `SkipFilters`
%%  parameter can be used to ignore clauses of some types, when creating
%%  the match specification.
%%
-spec message_filter_to_ms(list(), [atom()]) -> {ok, ets:match_spec()}.

message_filter_to_ms(MessageFilters, SkipFilters) ->
    MatchHead = #message{
        msg_id = ?MSG_MSVAR_ID,
        sender = ?MSG_MSVAR_SENDER,
        receiver = ?MSG_MSVAR_RECEIVER,
        date = ?MSG_MSVAR_DATE,
        _ = '_'
    },
    MatchBody = ['$_'],
    general_filter_to_ms(MessageFilters, SkipFilters, MatchHead, fun message_filter_to_guard/1, MatchBody).


%%
%% Takes message filter clause as a parameter and returns a list of its
%% corresponding match condition (guard) expressions for match specification.
%% If no guard should be returned, returns [].
%%
message_filter_to_guard({id, MsgIdOrList}) ->
    MakeGuardFun = fun(MsgId) ->
        case MsgId of
            {InstId, TrnNr, MsgNr} -> ok;
            {InstId, TrnNr, MsgNr, sent} -> ok;
            {InstId, TrnNr, MsgNr, recv} -> ok
        end,
        {'orelse',
            {'==', ?MSG_MSVAR_ID, {const, {InstId, TrnNr, MsgNr, sent}}},
            {'==', ?MSG_MSVAR_ID, {const, {InstId, TrnNr, MsgNr, recv}}}
        }
    end,
    make_orelse_guard(make_list(MsgIdOrList), MakeGuardFun);


message_filter_to_guard({date, undefined, undefined}) ->
    [];

message_filter_to_guard({date, From, undefined}) ->
    [
        {'>=', ?MSG_MSVAR_DATE, {const, From}}
    ];

message_filter_to_guard({date, undefined, Till}) ->
    [
        {'=<', ?MSG_MSVAR_DATE, {const, Till}}
    ];

message_filter_to_guard({date, From, Till}) ->
    [
        message_filter_to_guard({date, From, undefined}),
        message_filter_to_guard({date, undefined, Till})
    ];

message_filter_to_guard({peer, PeerOrList}) ->
    make_orelse_guard(make_list(PeerOrList), fun message_peer_filter_to_guard/1).


%%
%% Takes a single message peer filter clause value as a parameter and returns
%% a list of its corresponding match condition (guard) expressions for match
%% specification. Helper function to message_filter_to_guard/1.
%%
message_peer_filter_to_guard({sent, EventSrc}) ->
    {'==', ?MSG_MSVAR_SENDER, {const, EventSrc}};

message_peer_filter_to_guard({recv, EventSrc}) ->
    {'==', ?MSG_MSVAR_RECEIVER, {const, EventSrc}};

message_peer_filter_to_guard({any, EventSrc}) ->
    {'orelse',
        message_peer_filter_to_guard({sent, EventSrc}),
        message_peer_filter_to_guard({recv, EventSrc})
    }.


%% =============================================================================
%%  Other more general public functions
%% =============================================================================

%%
%%  sublist_opt(L, F, C) returns C elements of list L starting with F-th element of the list.
%%  L should be list, F - positive integer, C positive integer or 0.
%%
sublist_opt(List, From, _Count) when From > erlang:length(List) ->
    [];

sublist_opt(List, From, Count) ->
    lists:sublist(List, From, Count).


%%
%%  Converts list or single element to a list.
%%
make_list(List) when is_list(List) ->
    List;

make_list(Single) ->
    [Single].


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


%%
%%  Returns an intersection of lists.
%%  This function returns unique members, and threats lists as sets.
%%
intersect_lists([]) ->
    [];

intersect_lists([List]) ->
    List;

intersect_lists([List | Other]) ->
    MemberInOther = fun (E) ->
        member_in_all(E, Other)
    end,
    lists:filter(MemberInOther, lists:usort(List)).



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


