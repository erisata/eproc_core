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
-type fsm_ref()         :: {inst, inst_id()} | {name, term()} | {key, term()}.   % TODO: Rename, differentiate from inst_ref().
-type inst_name()       :: term().
-type inst_group()      :: eproc_fsm:group().
-type inst_status()     :: running | suspended | done | failed | killed.
-type store_ref()       :: eproc_store:ref().
-type registry_ref()    :: eproc_registry:ref().
-type trns_id()         :: integer().


-type trigger() ::
    {message, term()} |
    {timer, Name :: term(), Message :: term()} |
    {admin, Reason :: term()}.

%%
%%
%%
-record(instance, {
    id          :: inst_id(),
    group       :: inst_group(),
    name        :: inst_name(),
    keys        :: proplist(),
    props       :: proplist(),
    module      :: module(),
    args        :: term(),
    opts        :: proplist(),
    start_time  :: datetime(),
    status      :: inst_status(),
    archived    :: datetime()
}).


%%
%%
%%
-record(transition, {
    id          :: trns_id(),
    prev        :: trns_id(),
    inst_id     :: inst_id(),
    sname       :: term(),
    sdata       :: term(),
    timestamp   :: timestamp(),
    duration    :: duration(),
    trigger     :: trigger(),
    actions     :: list()
}).


