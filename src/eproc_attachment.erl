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
%%  Interface for storing fsm attachments. Attachment is a key value pair (possibly)
%%  belonging to some fsm.
%%
-module(eproc_attachment).
-compile([{parse_transform, lager_transform}]).
-export([save/5, load/2, delete/2, cleanup/2]).
-include("eproc.hrl").


%% =============================================================================
%%  Public API.
%% =============================================================================

%%
%%  This function saves attachment using Key as key and Value as value.
%%  If Owner is provided, the attacment is associated with the fsm and deleted,
%%  when fsm terminates. If Owner is undefined, attachment is stored until it is
%%  explicitelly deleted using delete/2. (NOTE: a possible source of memory leak)
%%  No options can currently be provided.
%%
-spec save(
        Store   :: store_ref(),
        Key     :: term(),
        Value   :: term(),
        Owner   :: fsm_ref() | undefined,
        Opts    :: proplists:proplist()
    ) ->
        ok | {error, Reason :: term()}.

save(Store, Key, Value, Owner, Opts) ->
    eproc_store:attachment_save(Store, Key, Value, Owner, Opts).


%%
%%  This function returns attachment value associated with given Key.
%%
-spec load(
        Store   :: store_ref(),
        Key     :: term()
    ) ->
        {ok, Value :: term()} |
        {error, Reason :: term()}.

load(Store, Key) ->
    eproc_store:attachment_load(Store, Key).


%%
%%  This function deletes attachment value associated with given Key.
%%
-spec delete(
        Store   :: store_ref(),
        Key :: term()
    ) ->
        ok | {error, Reason :: term()}.

delete(Store, Key) ->
    eproc_store:attachment_delete(Store, Key).


%%
%%  This function deletes all attachments associated with given fsm.
%%
-spec cleanup(
        Store   :: store_ref(),
        Owner :: fsm_ref()
    ) ->
        ok.

cleanup(Store, Owner) ->
    eproc_store:attachment_cleanup(Store, Owner).


