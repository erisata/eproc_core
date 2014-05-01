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
%%  This module is responsible for maintaining FSM metadata. For now,
%%  the metadata is maintained as tags, that can be attached to
%%  an FSM instance.
%%
%%  Tags can be used to find FSM instances or caregorize them.
%%  Tags don't need to be unique, but required to be binaries.
%%  They are maintained as FSM attributes.
%%
%%  TODO: Process versioning: api module provides metadata with versions and corresponding callback modules.
%%  TODO: Process descriptions, diagrams.
%%  TODO: State annotation.
%%  TODO: Event annotation.
%%  TODO: Transition annotation.
%%  TODO: Application / process group description?
%%
-module(eproc_meta).
-behaviour(eproc_fsm_attr).
-export([add_tag/2, get_instances/2]).
-export([init/1, handle_created/3, handle_updated/4, handle_removed/2, handle_event/3]).
-include("eproc.hrl").


-record(data, {
    tag     :: binary(),
    type    :: binary()
}).


%% =============================================================================
%%  Callback function definitions.
%% =============================================================================

%%
%%  TODO: ...
%%
-callback metadata(
        MetadataType    :: application | process | fsm
    ) ->
        {ok, todo}.



%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  Associate a tag with the current FSM instance.
%%  This function should be called from the FSM process, usually in
%%  the `handle_state/3` callback.
%%
-spec add_tag(
        Tag     :: binary() | integer() | atom() | list(),
        Type    :: binary() | integer() | atom() | list()
    ) ->
        ok.

add_tag(Tag, Type) ->
    Name = Action = {tag, to_binary(Tag), to_binary(Type)},
    eproc_fsm_attr:action(?MODULE, Name, Action, []).


%%
%%  Get FSM instances by specified query.
%%
%%  Currently the following options are supported:
%%
%%  `{store, Store}`
%%  :   Store to be used for the query. This option is mainly
%%      used for testing. The default store will be used by default.
%%
-spec get_instances(
        Query   :: {tags, [{Tag :: binary(), Type :: binary() | undefined}]},
        Opts    :: [{store, store_ref()}]
    ) ->
        {ok, [inst_id()]}.

get_instances(Query, Opts) ->
    eproc_fsm_attr:task(?MODULE, {get_instances, Query}, Opts).



%% =============================================================================
%%  Callbacks for `eproc_fsm_attr`.
%% =============================================================================

%%
%%  FSM started.
%%
init(ActiveAttrs) ->
    {ok, [ {A, undefined} || A <- ActiveAttrs ]}.


%%
%%  Attribute created.
%%
handle_created(_Attribute, {tag, Tag, Type}, _Scope) ->
    AttrData = #data{tag = Tag, type = Type},
    AttrState = undefined,
    {create, AttrData, AttrState, true}.


%%
%%  A tag can only be updated to the same value.
%%
handle_updated(Attribute, _AttrState, {tag, Tag, Type}, _Scope) ->
    #attribute{data = AttrData} = Attribute,
    AttrData = #data{tag = Tag, type = Type},
    handled.


%%
%%  Attributes should never be removed.
%%
handle_removed(_Attribute, _AttrState) ->
    {error, tags_non_removable}.


%%
%%  Events are not used for tags.
%%
handle_event(_Attribute, _AttrState, Event) ->
    throw({unknown_event, Event}).



%% =============================================================================
%%  Internal functions.
%% =============================================================================

%%
%%  Converts tags or tag types to binaries.
%%
to_binary(Value) when is_binary(Value) ->
    Value;

to_binary(Value) when is_atom(Value) ->
    erlang:atom_to_binary(Value, utf8);

to_binary(Value) when is_integer(Value) ->
    erlang:integer_to_binary(Value);

to_binary(Value) when is_list(Value) ->
    unicode:characters_to_binary(Value).


