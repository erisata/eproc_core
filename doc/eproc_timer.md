

# Module eproc_timer #
* [Function Index](#index)
* [Function Details](#functions)

__Behaviours:__ [`eproc_fsm_attr`](eproc_fsm_attr.md).
<a name="index"></a>

## Function Index ##


<table width="100%" border="1" cellspacing="0" cellpadding="2" summary="function index"><tr><td valign="top"><a href="#cancel-1">cancel/1</a></td><td></td></tr><tr><td valign="top"><a href="#duration_format-2">duration_format/2</a></td><td></td></tr><tr><td valign="top"><a href="#duration_parse-2">duration_parse/2</a></td><td></td></tr><tr><td valign="top"><a href="#duration_to_ms-1">duration_to_ms/1</a></td><td></td></tr><tr><td valign="top"><a href="#handle_created-4">handle_created/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_event-4">handle_event/4</a></td><td></td></tr><tr><td valign="top"><a href="#handle_removed-3">handle_removed/3</a></td><td></td></tr><tr><td valign="top"><a href="#handle_updated-5">handle_updated/5</a></td><td></td></tr><tr><td valign="top"><a href="#init-2">init/2</a></td><td></td></tr><tr><td valign="top"><a href="#set-2">set/2</a></td><td></td></tr><tr><td valign="top"><a href="#set-3">set/3</a></td><td></td></tr><tr><td valign="top"><a href="#set-4">set/4</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp-2">timestamp/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_after-2">timestamp_after/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_before-2">timestamp_before/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_diff-2">timestamp_diff/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_diff_us-2">timestamp_diff_us/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_format-2">timestamp_format/2</a></td><td></td></tr><tr><td valign="top"><a href="#timestamp_parse-2">timestamp_parse/2</a></td><td></td></tr></table>


<a name="functions"></a>

## Function Details ##

<a name="cancel-1"></a>

### cancel/1 ###


<pre><code>
cancel(Name::term()) -&gt; ok | {error, Reason::term()}
</code></pre>

<br></br>



<a name="duration_format-2"></a>

### duration_format/2 ###

`duration_format(Duration, X2) -> any()`


<a name="duration_parse-2"></a>

### duration_parse/2 ###

`duration_parse(Duration, Format) -> any()`


<a name="duration_to_ms-1"></a>

### duration_to_ms/1 ###


<pre><code>
duration_to_ms(Spec::<a href="#type-duration">duration()</a>) -&gt; integer()
</code></pre>

<br></br>



<a name="handle_created-4"></a>

### handle_created/4 ###

`handle_created(InstId, Attribute, X3, Scope) -> any()`


<a name="handle_event-4"></a>

### handle_event/4 ###

`handle_event(InstId, Attribute, State, X4) -> any()`


<a name="handle_removed-3"></a>

### handle_removed/3 ###

`handle_removed(InstId, Attribute, AttrState) -> any()`


<a name="handle_updated-5"></a>

### handle_updated/5 ###

`handle_updated(InstId, Attribute, AttrState, X4, Scope) -> any()`


<a name="init-2"></a>

### init/2 ###

`init(InstId, ActiveAttrs) -> any()`


<a name="set-2"></a>

### set/2 ###

`set(After, Event) -> any()`


<a name="set-3"></a>

### set/3 ###

`set(After, Event, Scope) -> any()`


<a name="set-4"></a>

### set/4 ###


<pre><code>
set(Name::term(), Time::<a href="#type-timestamp">timestamp()</a> | <a href="#type-duration">duration()</a>, Event::term(), Scope::<a href="#type-scope">scope()</a>) -&gt; ok
</code></pre>

<br></br>



<a name="timestamp-2"></a>

### timestamp/2 ###


<pre><code>
timestamp(DateTime::<a href="calendar.md#type-datetime">calendar:datetime()</a> | <a href="calendar.md#type-date">calendar:date()</a> | {<a href="calendar.md#type-date">calendar:date()</a>, <a href="calendar.md#type-time">calendar:time()</a>, USec::integer()} | undefined | null, Timezone::local | utc) -&gt; <a href="#type-timestamp">timestamp()</a> | undefined
</code></pre>

<br></br>



<a name="timestamp_after-2"></a>

### timestamp_after/2 ###


<pre><code>
timestamp_after(Duration::<a href="#type-duration">duration()</a>, X2::<a href="#type-timestamp">timestamp()</a>) -&gt; <a href="#type-timestamp">timestamp()</a>
</code></pre>

<br></br>



<a name="timestamp_before-2"></a>

### timestamp_before/2 ###


<pre><code>
timestamp_before(Duration::<a href="#type-duration">duration()</a>, Timestamp::<a href="#type-timestamp">timestamp()</a>) -&gt; <a href="#type-timestamp">timestamp()</a>
</code></pre>

<br></br>



<a name="timestamp_diff-2"></a>

### timestamp_diff/2 ###


<pre><code>
timestamp_diff(Timestamp2::<a href="#type-timestamp">timestamp()</a>, Timestamp1::<a href="#type-timestamp">timestamp()</a>) -&gt; <a href="#type-duration">duration()</a>
</code></pre>

<br></br>



<a name="timestamp_diff_us-2"></a>

### timestamp_diff_us/2 ###


<pre><code>
timestamp_diff_us(Timestamp2::<a href="#type-timestamp">timestamp()</a>, Timestamp1::<a href="#type-timestamp">timestamp()</a>) -&gt; <a href="#type-timestamp">timestamp()</a>
</code></pre>

<br></br>



<a name="timestamp_format-2"></a>

### timestamp_format/2 ###

`timestamp_format(Timestamp, X2) -> any()`


<a name="timestamp_parse-2"></a>

### timestamp_parse/2 ###

`timestamp_parse(TimestampBin, Format) -> any()`


