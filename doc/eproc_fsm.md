

# Module eproc_fsm #
* [Data Types](#types)
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`gen_server`](gen_server.md).

__This module defines the `eproc_fsm` behaviour.__
<br></br>
 Required callback functions: `init/1`, `init/2`, `handle_state/3`, `terminate/3`, `code_change/4`, `format_status/2`.

<a name="types"></a>

## Data Types ##




### <a name="type-group">group()</a> ###


__abstract datatype__: `group()`




### <a name="type-id">id()</a> ###


__abstract datatype__: `id()`




### <a name="type-name">name()</a> ###



<pre><code>
name() = {via, Registry::module(), InstId::<a href="#type-inst_id">inst_id()</a>}
</code></pre>





### <a name="type-start_spec">start_spec()</a> ###


__abstract datatype__: `start_spec()`




### <a name="type-state_data">state_data()</a> ###



<pre><code>
state_data() = term()
</code></pre>





### <a name="type-state_event">state_event()</a> ###



<pre><code>
state_event() = term()
</code></pre>





### <a name="type-state_name">state_name()</a> ###



<pre><code>
state_name() = list()
</code></pre>





### <a name="type-state_scope">state_scope()</a> ###



<pre><code>
state_scope() = list()
</code></pre>


<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#code_change-3">code_change/3</a></td><td></td></tr><tr><td valign="top"><a href="#create-3">create/3</a></td><td></td></tr><tr><td valign="top"><a href="#group-0">group/0</a></td><td></td></tr><tr><td valign="top"><a href="#handle_call-3">handle_call/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_cast-2">handle_cast/2</a></td><td></td></tr><tr><td valign="top"><a href="#handle_info-2">handle_info/2</a></td><td></td></tr><tr><td valign="top"><a href="#id-0">id/0</a></td><td></td></tr><tr><td valign="top"><a href="#init-1">init/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_fsm_ref-1">is_fsm_ref/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_next_state_valid-1">is_next_state_valid/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_online-1">is_online/1</a></td><td></td></tr><tr><td valign="top"><a href="#is_online-2">is_online/2</a></td><td></td></tr><tr><td valign="top"><a href="#is_state_in_scope-2">is_state_in_scope/2</a></td><td></td></tr><tr><td valign="top"><a href="#is_state_valid-1">is_state_valid/1</a></td><td></td></tr><tr><td valign="top"><a href="#kill-2">kill/2</a></td><td></td></tr><tr><td valign="top"><a href="#name-0">name/0</a></td><td></td></tr><tr><td valign="top"><a href="#register_resp_msg-6">register_resp_msg/6</a></td><td></td></tr><tr><td valign="top"><a href="#register_sent_msg-5">register_sent_msg/5</a></td><td></td></tr><tr><td valign="top"><a href="#registered_send-4">registered_send/4</a></td><td></td></tr><tr><td valign="top"><a href="#registered_sync_send-4">registered_sync_send/4</a></td><td></td></tr><tr><td valign="top"><a href="#reply-2">reply/2</a></td><td></td></tr><tr><td valign="top"><a href="#resolve_start_spec-2">resolve_start_spec/2</a></td><td></td></tr><tr><td valign="top"><a href="#resume-2">resume/2</a></td><td></td></tr><tr><td valign="top"><a href="#send_create_event-4">send_create_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#send_event-2">send_event/2</a></td><td></td></tr><tr><td valign="top"><a href="#send_event-3">send_event/3</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-2">start_link/2</a></td><td></td></tr><tr><td valign="top"><a href="#start_link-3">start_link/3</a></td><td></td></tr><tr><td valign="top"><a href="#suspend-1">suspend/1</a></td><td></td></tr><tr><td valign="top"><a href="#suspend-2">suspend/2</a></td><td></td></tr><tr><td valign="top"><a href="#sync_send_create_event-4">sync_send_create_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#sync_send_event-2">sync_send_event/2</a></td><td></td></tr><tr><td valign="top"><a href="#sync_send_event-3">sync_send_event/3</a></td><td></td></tr><tr><td valign="top"><a href="#terminate-2">terminate/2</a></td><td></td></tr><tr><td valign="top"><a href="#update-5">update/5</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="code_change-3"></a>

### code_change/3 ###

`code_change(OldVsn, State, Extra) -> any()`


<a name="create-3"></a>

### create/3 ###


<pre><code>
create(Module::module(), Args::term(), Options::<a href="#type-proplist">proplist()</a>) -&gt; {ok, <a href="#type-fsm_ref">fsm_ref()</a>} | {error, {already_created, <a href="#type-fsm_ref">fsm_ref()</a>}}
</code></pre>

<br></br>



<a name="group-0"></a>

### group/0 ###


<pre><code>
group() -&gt; {ok, <a href="#type-group">group()</a>} | {error, not_fsm}
</code></pre>

<br></br>



<a name="handle_call-3"></a>

### handle_call/3 ###

`handle_call(X1, From, State) -> any()`


<a name="handle_cast-2"></a>

### handle_cast/2 ###

`handle_cast(X1, State) -> any()`


<a name="handle_info-2"></a>

### handle_info/2 ###

`handle_info(Event, State) -> any()`


<a name="id-0"></a>

### id/0 ###


<pre><code>
id() -&gt; {ok, <a href="#type-id">id()</a>} | {error, not_fsm}
</code></pre>

<br></br>



<a name="init-1"></a>

### init/1 ###

`init(X1) -> any()`


<a name="is_fsm_ref-1"></a>

### is_fsm_ref/1 ###


<pre><code>
is_fsm_ref(X1::<a href="#type-fsm_ref">fsm_ref()</a> | term()) -&gt; boolean()
</code></pre>

<br></br>



<a name="is_next_state_valid-1"></a>

### is_next_state_valid/1 ###


<pre><code>
is_next_state_valid(State::<a href="#type-state_name">state_name()</a>) -&gt; boolean()
</code></pre>

<br></br>



<a name="is_online-1"></a>

### is_online/1 ###


<pre><code>
is_online(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-otp_ref">otp_ref()</a>) -&gt; boolean()
</code></pre>

<br></br>



<a name="is_online-2"></a>

### is_online/2 ###


<pre><code>
is_online(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-otp_ref">otp_ref()</a>, Options::list()) -&gt; boolean()
</code></pre>

<br></br>



<a name="is_state_in_scope-2"></a>

### is_state_in_scope/2 ###


<pre><code>
is_state_in_scope(State::<a href="#type-state_name">state_name()</a>, Scope::<a href="#type-state_scope">state_scope()</a>) -&gt; boolean()
</code></pre>

<br></br>



<a name="is_state_valid-1"></a>

### is_state_valid/1 ###


<pre><code>
is_state_valid(SubStates::<a href="#type-state_name">state_name()</a>) -&gt; boolean()
</code></pre>

<br></br>



<a name="kill-2"></a>

### kill/2 ###


<pre><code>
kill(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-otp_ref">otp_ref()</a>, Options::list()) -&gt; {ok, ResolvedFsmRef::<a href="#type-fsm_ref">fsm_ref()</a>} | {error, bad_ref} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="name-0"></a>

### name/0 ###


<pre><code>
name() -&gt; {ok, <a href="#type-name">name()</a>} | {error, not_fsm}
</code></pre>

<br></br>



<a name="register_resp_msg-6"></a>

### register_resp_msg/6 ###


<pre><code>
register_resp_msg(Src::<a href="#type-event_src">event_src()</a>, Dst::<a href="#type-event_src">event_src()</a>, SentMsgCId::<a href="#type-msg_cid">msg_cid()</a>, RespMsgCId::<a href="#type-msg_cid">msg_cid()</a> | undefined, RespMsg::term(), Timestamp::<a href="#type-timestamp">timestamp()</a>) -&gt; {ok, <a href="#type-msg_cid">msg_cid()</a>} | {error, no_sent}
</code></pre>

<br></br>



<a name="register_sent_msg-5"></a>

### register_sent_msg/5 ###


<pre><code>
register_sent_msg(Src::<a href="#type-event_src">event_src()</a>, Dst::<a href="#type-event_src">event_src()</a>, SentMsgCId::<a href="#type-msg_cid">msg_cid()</a> | undefined, SentMsg::term(), Timestamp::<a href="#type-timestamp">timestamp()</a>) -&gt; {ok, <a href="#type-msg_cid">msg_cid()</a>} | {error, not_fsm}
</code></pre>

<br></br>



<a name="registered_send-4"></a>

### registered_send/4 ###

`registered_send(EventSrc, EventDst, Event, SendFun) -> any()`


<a name="registered_sync_send-4"></a>

### registered_sync_send/4 ###

`registered_sync_send(EventSrc, EventDst, Event, SendFun) -> any()`


<a name="reply-2"></a>

### reply/2 ###


<pre><code>
reply(To::term(), Reply::<a href="#type-state_event">state_event()</a>) -&gt; ok | {error, Reason::term()}
</code></pre>

<br></br>



<a name="resolve_start_spec-2"></a>

### resolve_start_spec/2 ###


<pre><code>
resolve_start_spec(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, StartSpec::<a href="#type-start_spec">start_spec()</a>) -&gt; {start_link_args, Args::list()} | {start_link_mfa, {Module::module(), Function::atom(), Args::list()}}
</code></pre>

<br></br>



<a name="resume-2"></a>

### resume/2 ###


<pre><code>
resume(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-otp_ref">otp_ref()</a>, Options::list()) -&gt; {ok, ResolvedFsmRef::<a href="#type-fsm_ref">fsm_ref()</a>} | {error, bad_ref} | {error, running} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="send_create_event-4"></a>

### send_create_event/4 ###


<pre><code>
send_create_event(Module::module(), Args::term(), Event::<a href="#type-state_event">state_event()</a>, Options::<a href="#type-proplist">proplist()</a>) -&gt; {ok, <a href="#type-fsm_ref">fsm_ref()</a>} | {error, {already_created, <a href="#type-fsm_ref">fsm_ref()</a>}} | {error, timeout} | {error, term()}
</code></pre>

<br></br>



<a name="send_event-2"></a>

### send_event/2 ###


<pre><code>
send_event(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-fsm_key">fsm_key()</a> | <a href="#type-otp_ref">otp_ref()</a>, Event::term()) -&gt; ok
</code></pre>

<br></br>



<a name="send_event-3"></a>

### send_event/3 ###


<pre><code>
send_event(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-fsm_key">fsm_key()</a> | <a href="#type-otp_ref">otp_ref()</a>, Event::term(), Options::<a href="#type-proplist">proplist()</a>) -&gt; ok
</code></pre>

<br></br>



<a name="start_link-2"></a>

### start_link/2 ###


<pre><code>
start_link(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, Options::<a href="#type-proplist">proplist()</a>) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>

<br></br>



<a name="start_link-3"></a>

### start_link/3 ###


<pre><code>
start_link(FsmName::{local, atom()} | {global, term()} | {via, module(), term()}, FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, Options::<a href="#type-proplist">proplist()</a>) -&gt; {ok, pid()} | ignore | {error, term()}
</code></pre>

<br></br>



<a name="suspend-1"></a>

### suspend/1 ###


<pre><code>
suspend(Reason::term()) -&gt; ok
</code></pre>

<br></br>



<a name="suspend-2"></a>

### suspend/2 ###


<pre><code>
suspend(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, Options::list()) -&gt; {ok, ResolvedFsmRef::<a href="#type-fsm_ref">fsm_ref()</a>} | {error, bad_ref} | {error, Reason::term()}
</code></pre>

<br></br>



<a name="sync_send_create_event-4"></a>

### sync_send_create_event/4 ###


<pre><code>
sync_send_create_event(Module::module(), Args::term(), Event::<a href="#type-state_event">state_event()</a>, Options::<a href="#type-proplist">proplist()</a>) -&gt; {ok, <a href="#type-fsm_ref">fsm_ref()</a>, Reply::term()} | {error, {already_created, <a href="#type-fsm_ref">fsm_ref()</a>}} | {error, timeout} | {error, term()}
</code></pre>

<br></br>



<a name="sync_send_event-2"></a>

### sync_send_event/2 ###


<pre><code>
sync_send_event(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-fsm_key">fsm_key()</a> | <a href="#type-otp_ref">otp_ref()</a>, Event::term()) -&gt; ok
</code></pre>

<br></br>



<a name="sync_send_event-3"></a>

### sync_send_event/3 ###


<pre><code>
sync_send_event(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a> | <a href="#type-fsm_key">fsm_key()</a> | <a href="#type-otp_ref">otp_ref()</a>, Event::term(), Options::<a href="#type-proplist">proplist()</a>) -&gt; Reply::term()
</code></pre>

<br></br>



<a name="terminate-2"></a>

### terminate/2 ###

`terminate(Reason, State) -> any()`


<a name="update-5"></a>

### update/5 ###


<pre><code>
update(FsmRef::<a href="#type-fsm_ref">fsm_ref()</a>, NewStateName::<a href="#type-state_name">state_name()</a> | undefined, NewStateData::<a href="#type-state_data">state_data()</a> | undefined, UpdateScript::<a href="#type-script">script()</a> | undefined, Options::list()) -&gt; {ok, ResolvedFsmRef::<a href="#type-fsm_ref">fsm_ref()</a>} | {error, Reason::term()}
</code></pre>

<br></br>



