%/--------------------------------------------------------------------
%| Copyright 2013 Karolis Petrauskas
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

-type proplist()        :: [{term(), term()}].
-type datetime()        :: calendar:datetime().     % {Date, Time} in UTC
-type timestamp()       :: erlang:timestamp().      % {Mega, Secs, Micro}
-type duration()        :: integer().               % in ms.
-type inst_id()         :: eproc_fsm:id().
-type inst_ref()        :: eproc_fsm:ref().
-type inst_name()       :: term().
-type inst_group()      :: eproc_fsm:group().
-type inst_status()     :: running | suspended | done | failed | killed.
-type store_ref()       :: eproc_store:ref().
-type registry_ref()    :: eproc_registry:ref().
-type trns_id()         :: integer().


%%
%%
%%
-record(definition, {
    application         :: atom(),
    process             :: atom(),
    version = [0, 0, 0] :: list(),
    module              :: module(),
    args                :: term(),
    description         :: binary(),
    valid_from          :: timestamp(), % Inclusive
    valid_till          :: timestamp(), % Exclusive
    options = []        :: list()
}).

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
    module      :: module(),        %% TODO: Change it to definition?
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


