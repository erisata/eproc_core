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
%%  This module handles generic part of FSM attributes.
%%  FSM attribute is a mechanism for extending FSM at a system level.
%%  Several extensions are provided within `eproc_core`, and other
%%  implementations can also be provided by an user.
%%
%%  TODO: Better error messages: duplicate attr in one trn.
%%  TODO: Better error messages: attr created out of scope.
%%
-module(eproc_fsm_attr).
-compile([{parse_transform, lager_transform}]).
-export([describe/2]).
-export([action/4, action/3, task/3, make_event/2]).
-export([apply_actions/4]).
-export([init/5, transition_start/4, transition_end/4, event/3]).
-include("eproc.hrl").


-record(attr_ctx, {
    attr_nr :: attr_nr(),       %%  Attribute Nr.
    attr    :: #attribute{},    %%  Attribute info.
    state   :: term()           %%  Runtime state of the attribute.
}).

-record(state, {
    last_nr :: attr_nr(),       %%  Last used attribute ID.
    attrs   :: [#attr_ctx{}],   %%  Contexts for all active attributes of the FSM.
    store   :: store_ref()
}).

-record(trn_ctx, {
    inst_id :: inst_id(),
    trn_nr  :: trn_nr(),
    sname   :: term(),
    store   :: store_ref()
}).


%% =============================================================================
%%  Callback definitions.
%% =============================================================================

%%
%%  Invoked when FSM started or restarted.
%%
-callback init(
        InstId      :: inst_id(),
        ActiveAttrs :: [#attribute{}]
    ) ->
        {ok, [{Attribute, AttrState}]} |
        {error, Reason}
    when
        Attribute :: #attribute{},
        AttrState :: term(),
        Reason :: term().


%%
%%  Asks to decribe the provided attribute. The returned values
%%  should not expose any internal data structures, etc.
%%
%%  This callback will usually be called not from the process of the FSM.
%%
-callback handle_describe(
        Attribute   :: #attribute{},
        What        :: [PropName :: atom()] | all
    ) ->
        {ok, [{PropName :: atom(), PropValue :: term()}]}.


%%
%%  Attribute created.
%%  This callback will always be called in the scope of transition.
%%
-callback handle_created(
        InstId      :: inst_id(),
        Attribute   :: #attribute{},
        Action      :: term(),
        Scope       :: term()
    ) ->
        {create, Data, State, NeedsStore} |
        {error, Reason}
    when
        Data :: term(),
        State :: term(),
        Reason :: term(),
        NeedsStore :: boolean().


%%
%%  Attribute updated by user.
%%  This callback will always be called in the scope of transition.
%%
-callback handle_updated(
        InstId      :: inst_id(),
        Attribute   :: #attribute{},
        AttrState   :: term(),
        Action      :: term(),
        Scope       :: term() | undefined
    ) ->
        {update, NewData, NewState, NeedsStore} |
        {remove, Reason, NeedsStore} |
        handled |
        {error, Reason}
    when
        NewData :: term(),
        NewState :: term(),
        Reason :: term(),
        NeedsStore :: boolean().


%%
%%  Attribute removed by `eproc_fsm`.
%%  This callback will always be called in the scope of transition.
%%
-callback handle_removed(
        InstId      :: inst_id(),
        Attribute   :: #attribute{},
        AttrState   :: term()
    ) ->
        {ok, NeedsStore} |
        {error, Reason}
    when
        Reason :: term(),
        NeedsStore :: boolean().


%%
%%  Notifies about an event, received by the attribute.
%%  This handler can update attribute's runtime state and
%%  optionally initiate an FSM transition by providing its
%%  trigger.
%%
-callback handle_event(
        InstId      :: inst_id(),
        Attribute   :: #attribute{},
        AttrState   :: term(),
        Event       :: term()
    ) ->
        {handled, NewAttrState} |
        {trigger, Trigger, Action, NeedsStore} |
        {error, Reason}
    when
        NewAttrState :: term(),
        NewAttrData :: term(),
        Trigger     :: #trigger_spec{},
        Action ::
            {update, NewAttrData, NewAttrState} |
            {remove, Reason},
        Reason :: term(),
        NeedsStore :: boolean().



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Describe attribute data.
%%
-spec describe(#attribute{}, [atom()] | all) -> {ok, [{atom(), term()}]}.

describe(Attribute = #attribute{module = Module}, What) ->
    Module:handle_describe(Attribute, What).



%% =============================================================================
%%  Functions for `eproc_fsm_attr` callback implementations.
%% =============================================================================


%%
%%  Registers new user action.
%%
action(Module, Name, Action, Scope) ->
    Actions = erlang:get('eproc_fsm_attr$actions'),
    erlang:put('eproc_fsm_attr$actions', [{Module, Name, Action, Scope} | Actions]),
    ok.


%%
%%  Registers new user action.
%%
action(Module, Name, Action) ->
    action(Module, Name, Action, undefined).


%%
%%  Performs Attribute task in the store.
%%
task(Module, Task, Opts) ->
    Store = case proplists:get_value(store, Opts, undefined) of
        undefined ->
            case erlang:get('eproc_fsm_attr$trn_ctx') of
                undefined ->
                    undefined;
                #trn_ctx{store = CtxStore} ->
                    CtxStore
            end;
        OptsStore ->
            OptsStore
    end,
    eproc_store:attr_task(Store, Module, Task).


%%
%%  Returns a message, that can be sent to the FSM process. It will be recognized
%%  as a message sent to the particular attribute and its handler.
%%
make_event(AttrRef, Event) ->
    {ok, {'eproc_fsm_attr$event', AttrRef, Event}}.



%% =============================================================================
%%  Functions for `eproc_fsm`.
%% =============================================================================

%%
%%  Invoked, when the corresponding FSM is started (become online).
%%
init(InstId, _SName, LastId, Store, ActiveAttrs) ->
    State = #state{
        last_nr = LastId,
        attrs = init_on_start(InstId, ActiveAttrs, []),
        store = Store
    },
    {ok, State}.


%%
%%  Invoked at the start of each transition.
%%
transition_start(InstId, TrnNr, SName, State = #state{store = Store}) ->
    erlang:put('eproc_fsm_attr$actions', []),
    erlang:put('eproc_fsm_attr$trn_ctx', #trn_ctx{inst_id = InstId, trn_nr = TrnNr, sname = SName, store = Store}),
    {ok, State}.


%%
%%  Invoked at the end of each transition.
%%
transition_end(InstId, TrnNr, NextSName, State = #state{last_nr = LastAttrNr, attrs = AttrCtxs}) ->
    erlang:erase('eproc_fsm_attr$trn_ctx'),
    ActionSpecs = lists:reverse(erlang:erase('eproc_fsm_attr$actions')),
    {AttrCtxsAfterActions, UserActions, _, NewAttrNr} = lists:foldl(
        fun perform_action/2,
        {AttrCtxs, [], {InstId, TrnNr, NextSName}, LastAttrNr},
        ActionSpecs
    ),
    {InstId, NextSName, AttrCtxsAfterCleanup, CleanupActions} = lists:foldl(
        fun perform_cleanup/2,
        {InstId, NextSName, [], []},
        AttrCtxsAfterActions
    ),
    AllActions = lists:reverse(UserActions) ++ CleanupActions,
    NewState = State#state{
        last_nr = NewAttrNr,
        attrs = AttrCtxsAfterCleanup
    },
    {ok, AllActions, NewAttrNr, NewState}.


%%
%%  Invoked, when the FSM receives an unknown event.
%%
event(InstId, {'eproc_fsm_attr$event', AttrRef, Event}, State = #state{attrs = AttrCtxs}) ->
    Found = case AttrRef of
        {name, undefined} ->
            lager:error("Ignoring attribute event with name=undefined for inst_id=~p", [InstId]),
            {error, not_found};
        {name, Name} ->
            case [ AC || AC = #attr_ctx{attr = #attribute{name = N}} <- AttrCtxs, N =:= Name ] of
                [] ->
                    lager:error("Ignoring attribute event with unknown name=~p for inst_id=~p", [Name, InstId]),
                    {error, not_found};
                [AC] ->
                    {ok, AC}
            end;
        {id, RefAttrNr} ->
            case lists:keyfind(RefAttrNr, #attr_ctx.attr_nr, AttrCtxs) of
                false ->
                    lager:error("Ignoring attribute event with unknown id=~p for inst_id=~p", [RefAttrNr, InstId]),
                    {error, not_found};
                 AC ->
                    {ok, AC}
            end
    end,
    case Found of
        {error, _Reason} ->
            % Already logged above.
            {handled, State};
        {ok, AttrCtx = #attr_ctx{attr_nr = AttrNr}} ->
            case process_event(InstId, AttrCtx, Event) of
                {handled, NewAttrCtx} ->
                    NewAttrCtxs = lists:keyreplace(AttrNr, #attr_ctx.attr_nr, AttrCtxs, NewAttrCtx),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {handled, NewState};
                {trigger, removed, Trigger, AttrAction} ->
                    NewAttrCtxs = lists:keydelete(AttrNr, #attr_ctx.attr_nr, AttrCtxs),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {trigger, NewState, Trigger, AttrAction};
                {trigger, NewAttrCtx, Trigger, AttrAction} ->
                    NewAttrCtxs = lists:keyreplace(AttrNr, #attr_ctx.attr_nr, AttrCtxs, NewAttrCtx),
                    NewState = State#state{attrs = NewAttrCtxs},
                    {trigger, NewState, Trigger, AttrAction}
            end
    end;

event(_InstId, _Event, _State) ->
    unknown.



%% =============================================================================
%%  Functions for `eproc_store`.
%% =============================================================================

%%
%%  Replays actions of the specific transition on initial attributes.
%%
-spec apply_actions(
        AttrActions :: [#attr_action{}] | undefined,
        Attributes  :: [#attribute{}],
        InstId      :: inst_id(),
        TrnNr       :: trn_nr()
    ) ->
        {ok, [#attribute{}]}.

apply_actions(undefined, Attributes, _InstId, _TrnNr) ->
    {ok, Attributes};

apply_actions(AttrActions, Attributes, InstId, TrnNr) ->
    FoldFun = fun (Action, Attrs) ->
        apply_action(Action, Attrs, InstId, TrnNr)
    end,
    NewAttrs = lists:foldl(FoldFun, Attributes, AttrActions),
    {ok, NewAttrs}.


%%
%%  Replays single attribute action.
%%  Returns a list of active attributes after applying the provided attribute action.
%%  Its an internal function, helper for `apply_actions/4`.
%%
apply_action(#attr_action{module = Module, attr_nr = AttrNr, action = Action}, Attrs, _InstId, TrnNr) ->
    case Action of
        {create, Name, Scope, Data} ->
            NewAttr = #attribute{
                attr_id = AttrNr,
                module = Module,
                name = Name,
                scope = Scope,
                data = Data,
                from = TrnNr,
                upds = [],
                till = undefined,
                reason = undefined
            },
            [NewAttr | Attrs];
        {update, NewScope, NewData} ->
            Attr = #attribute{upds = Upds} = lists:keyfind(AttrNr, #attribute.attr_id, Attrs),
            NewAttr = Attr#attribute{
                scope = NewScope,
                data = NewData,
                upds = [TrnNr | Upds]
            },
            lists:keyreplace(AttrNr, #attribute.attr_id, Attrs, NewAttr);
        {remove, _Reason} ->
            lists:keydelete(AttrNr, #attribute.attr_id, Attrs)
    end.



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%
%%
init_on_start(_InstId, [], Started) ->
    Started;

init_on_start(InstId, ActiveAttrs = [#attribute{module = Module} | _], Started) ->
    {Similar, Other} = lists:partition(fun (#attribute{module = M}) -> M =:= Module end, ActiveAttrs),
    case Module:init(InstId, Similar) of
        {ok, SimilarStarted} ->
            ConvertFun = fun ({A = #attribute{attr_id = ANR}, S}) ->
                #attr_ctx{attr_nr = ANR, attr = A, state = S}
            end,
            init_on_start(InstId, Other, lists:map(ConvertFun, SimilarStarted) ++ Started);
        {error, Reason} ->
            erlang:throw({attr_init_failed, Reason})
    end.


%%
%%  Perform user actions on attributes.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_action(ActionSpec, {AttrCtxs, Actions, Context, LastAttrNr}) ->
    {Module, Name, Action, Scope} = ActionSpec,
    case Name of
        undefined ->
            {ok, NewAttrCtx, NewAction, NewAttrNr} = perform_create(Module, Name, Action, Scope, Context, LastAttrNr),
            {[NewAttrCtx | AttrCtxs], [NewAction | Actions], Context, NewAttrNr};
        _ ->
            ByNameFun = fun (#attr_ctx{attr = #attribute{name = N}}) -> N =:= Name end,
            case lists:partition(ByNameFun, AttrCtxs) of
                {[], AttrCtxs} ->
                    {ok, NewAttrCtx, NewAction, NewAttrNr} = perform_create(Module, Name, Action, Scope, Context, LastAttrNr),
                    {[NewAttrCtx | AttrCtxs], [NewAction | Actions], Context, NewAttrNr};
                {[AttrCtx], OtherAttrCtxs} ->
                    case perform_update(AttrCtx, Action, Scope, Context) of
                        {updated, NewAttrCtx, NewAction} ->
                            {[NewAttrCtx | OtherAttrCtxs], [NewAction | Actions], Context, LastAttrNr};
                        {removed, NewAction} ->
                            {OtherAttrCtxs, [NewAction | Actions], Context, LastAttrNr};
                        handled ->
                            {[AttrCtx | OtherAttrCtxs], Actions, Context, LastAttrNr}
                    end
            end
    end.


%%
%%  Create new attribute.
%%
perform_create(Module, Name, Action, Scope, {InstId, TrnNr, NextSName}, LastAttrNr) ->
    ResolvedScope = resolve_scope(Scope, undefined, NextSName),
    NewAttrNr = LastAttrNr + 1,
    NewAttribute = #attribute{
        attr_id = NewAttrNr,
        module = Module,
        name = Name,
        scope = ResolvedScope,
        data = undefined,
        from = TrnNr,
        upds = [],
        till = undefined
    },
    case Module:handle_created(InstId, NewAttribute, Action, ResolvedScope) of
        {create, AttrData, AttrState, NeedsStore} ->
            AttrCtx = #attr_ctx{
                attr_nr = NewAttrNr,
                attr = NewAttribute#attribute{data = AttrData},
                state = AttrState
            },
            AttrAction = #attr_action{
                module = Module,
                attr_nr = NewAttrNr,
                action = {create, Name, ResolvedScope, AttrData},
                needs_store = NeedsStore
            },
            {ok, AttrCtx, AttrAction, NewAttrNr};
        {error, Reason} ->
            erlang:throw({attr_create_failed, Reason})
    end.


%%
%%  Update existing attribute.
%%
perform_update(AttrCtx, Action, Scope, {InstId, TrnNr, NextSName}) ->
    #attr_ctx{
        attr = Attribute,
        state = AttrState
    } = AttrCtx,
    #attribute{
        attr_id = AttrNr,
        module = Module,
        scope = OldScope,
        upds = Upds
    } = Attribute,
    ResolvedScope = resolve_scope(Scope, OldScope, NextSName),
    case Module:handle_updated(InstId, Attribute, AttrState, Action, Scope) of
        {update, NewData, NewState, NeedsStore} ->
            AttrAction = #attr_action{
                module = Module,
                attr_nr = AttrNr,
                action = {update, ResolvedScope, NewData},
                needs_store = NeedsStore
            },
            NewAttribute = Attribute#attribute{
                data = NewData,
                scope = ResolvedScope,
                upds = [TrnNr | Upds]
            },
            NewAttrCtx = AttrCtx#attr_ctx{
                attr = NewAttribute,
                state = NewState
            },
            {updated, NewAttrCtx, AttrAction};
        {remove, UserReason, NeedsStore} ->
            AttrAction = #attr_action{
                module = Module,
                attr_nr = AttrNr,
                action = {remove, {user, UserReason}},
                needs_store = NeedsStore
            },
            {removed, AttrAction};
        handled ->
            handled;
        {error, Reason} ->
            erlang:throw({attr_update_failed, Reason})
    end.


%%
%%  Cleanup attributes, that became out-of-scope.
%%  This function is designed to be used with `lists:folfl/3`.
%%
perform_cleanup(AttrCtx, {InstId, SName, AttrCtxs, Actions}) ->
    #attr_ctx{attr = Attr, state = State} = AttrCtx,
    #attribute{attr_id = AttrNr, module = Module, scope = Scope} = Attr,
    case eproc_fsm:is_state_in_scope(SName, Scope) of
        true ->
            {InstId, SName, [AttrCtx | AttrCtxs], Actions};
        false ->
            case Module:handle_removed(InstId, Attr, State) of
                {ok, NeedsStore} ->
                    Action = #attr_action{
                        module = Module,
                        attr_nr = AttrNr,
                        action = {remove, {scope, SName}},
                        needs_store = NeedsStore
                    },
                    {InstId, SName, AttrCtxs, [Action | Actions]};
                {error, Reason} ->
                    erlang:throw({attr_cleanup_failed, Reason})
            end
    end.


%%
%%
%%
process_event(InstId, AttrCtx, Event) ->
    #attr_ctx{attr = Attribute, state = AttrState} = AttrCtx,
    #attribute{attr_id = AttrNr, module = Module, scope = Scope} = Attribute,
    case Module:handle_event(InstId, Attribute, AttrState, Event) of
        {handled, NewAttrState} ->
            NewAttrCtx = AttrCtx#attr_ctx{state = NewAttrState},
            {handled, NewAttrCtx};
        {trigger, Trigger, {remove, Reason}, NeedsStore} when is_record(Trigger, trigger_spec) ->
            AttrAction = #attr_action{
                module = Module,
                attr_nr = AttrNr,
                action = {remove, {user, Reason}},
                needs_store = NeedsStore
            },
            {trigger, removed, Trigger, AttrAction};
        {trigger, Trigger, {update, NewAttrData, NewAttrState}, NeedsStore} when is_record(Trigger, trigger_spec) ->
            NewAttrCtx = AttrCtx#attr_ctx{
                attr = Attribute#attribute{data = NewAttrData},
                state = NewAttrState
            },
            AttrAction = #attr_action{
                module = Module,
                attr_nr = AttrNr,
                action = {update, Scope, NewAttrData},
                needs_store = NeedsStore
            },
            {trigger, NewAttrCtx, Trigger, AttrAction};
        {error, Reason} ->
            erlang:throw({attr_event_failed, Reason})
    end.


%%
%%
%%
resolve_scope(Scope, OldScope, NextSName) when Scope =/= undefined; OldScope =/= undefined ->
    case Scope of
        next      -> NextSName;
        undefined -> OldScope;
        _         -> Scope
    end.


