from __future__ import annotations

import math
from typing import Any

from radio_agent.schemas import (
  RadioGenerateRequest,
  RadioGeneratedItem,
  RadioTrack,
  RadioTransitionCopy,
)
from radio_agent.state_helpers import (
  AgentState,
  first_recommended_id,
  track_summary,
  transition_id,
  valid_transition_pairs,
)


def mock_entry_payload(state: AgentState) -> dict[str, Any]:
  request = state["request"]
  first_item_id = first_recommended_id(state)
  first_track = track_summary(state, first_item_id)
  is_english = _is_english(request)

  if first_track:
    mood = _mood_label(first_track)
    if is_english:
      text = (
        f"Welcome to Airset. We'll start with {first_track['title']}, because "
        f"{first_track['artist']}'s {mood} tone gives us an easy place to land. "
        "Stay with me for a minute; I'll keep the set close enough to feel familiar, "
        "with a little room for something new. Nothing dramatic, just a friendly "
        "opening stretch while the first track settles in."
      )
      display_text = f"Opening with {first_track['title']}, keeping this stretch warm and familiar."
    else:
      text = (
        f"嗯，欢迎调到 Airset。我们先从《{first_track['title']}》开始，"
        f"让 {first_track['artist']} 的{mood}把这一段慢慢带起来。"
      )
      display_text = f"从《{first_track['title']}》开始，进入这段{mood}电台。"
  else:
    text = (
      "No playable candidates are available for this station yet. "
      "I'll keep the dial warm until a playable track is ready."
      if is_english
      else "这个电台暂时没有可播放候选。"
    )
    display_text = text

  if not first_track and request.seedTracks:
    text = default_intro(request)
    display_text = text

  return {
    "id": "station-intro",
    "text": text,
    "displayText": display_text,
    "targetItemId": first_item_id,
    "agent": "entry_copy_agent",
  }


def mock_transition_payload(state: AgentState) -> dict[str, Any]:
  return {
    "betweenTracks": [
      mock_transition_copy(state, pair).model_dump()
      for pair in valid_transition_pairs(state)
    ]
  }


def mock_transition_copy(state: AgentState, pair: tuple[str, str]) -> RadioTransitionCopy:
  pairs = valid_transition_pairs(state)
  from_track = track_summary(state, pair[0])
  to_track = track_summary(state, pair[1])
  if from_track and to_track:
    text, display_text = _transition_copy_for_pair(
      state["request"],
      from_track,
      to_track,
      _pair_index(pair, pairs),
    )
  else:
    text = (
      "Airset is keeping the station moving, so the silence does not have to do all the work. "
      "Stay with me for a moment; I will keep this handoff gentle while the next playable track gets ready. "
      "The idea is not to force a big reveal, just to keep the room warm until the music can take over again."
      if _is_english(state["request"])
      else "Airset 正在把电台带向下一首。"
    )
    display_text = text

  return RadioTransitionCopy(
    id=transition_id(pair, pairs),
    fromItemId=pair[0],
    toItemId=pair[1],
    text=text,
    displayText=display_text,
    agent="transition_copy_agent",
  )


def _transition_copy_for_pair(
  request: RadioGenerateRequest,
  from_track: dict[str, Any],
  to_track: dict[str, Any],
  index: int,
) -> tuple[str, str]:
  to_mood = _mood_label(to_track)
  from_mood = _mood_label(from_track)
  is_english = _is_english(request)
  to_title = str(to_track.get("title") or ("the next track" if is_english else "下一首"))
  from_title = str(from_track.get("title") or ("that last track" if is_english else "刚才那首"))
  to_artist = str(to_track.get("artist") or ("this artist" if is_english else "这位音乐人"))

  if _same_clean_value(from_track.get("artist"), to_track.get("artist")):
    if is_english:
      return (
        f"{from_title} keeps us close to {to_artist}, so we do not need to hurry the turn. "
        f"There is already a clear thread here, and I like letting it breathe instead of jumping away too quickly. "
        f"Stay with me; {to_title} carries that same feeling a little farther, like a friend turning over one more card from the same stack.",
        f"Staying with {to_artist} as {to_title} carries the thread forward.",
      )
    return (
      f"好，刚才的《{from_title}》还在同一个气口里。我们继续听 {to_artist}，让《{to_title}》把这条线再往前推一点。",
      f"继续听 {to_artist}，把气氛交给《{to_title}》。",
    )

  if _same_clean_value(from_track.get("album"), to_track.get("album")):
    if is_english:
      return (
        f"These two feel like different light from the same room, so let's not rush the door closed. "
        f"{from_title} already put us inside that space, and the nicest move is to notice another corner of it. "
        f"After that, {to_title} gives the set a softer edge without making the whole mood start over.",
        f"Another side of the album: {to_title}.",
      )
    return (
      f"嗯，这两首其实像同一张照片里的两块光影。《{from_title}》收住以后，换《{to_title}》把边缘放软。",
      f"同一张专辑的另一面，交给《{to_title}》。",
    )

  lane = str(to_track.get("sourceLane") or "").replace("_", " ").strip().lower()
  signals = " ".join(str(value).lower() for value in to_track.get("reasonSignals") or [])
  if "familiar" in lane or "anchor" in lane or "familiar" in signals:
    if is_english:
      return (
        f"That last track warmed up the room, and I would rather hold that glow than snap away from it. "
        f"It feels better to keep something familiar within reach while the set turns, almost like leaving a light on in the next room. "
        f"{to_title} keeps that part close, then lets the mood move forward at its own pace.",
        f"Holding the familiar glow a little longer with {to_title}.",
      )
    return (
      f"刚才那首把耳朵热起来了。下一段我们不急着跳开，用《{to_title}》留住一点熟悉的温度。",
      f"留住一点熟悉感，听《{to_title}》。",
    )

  if "discover" in lane or "catalog" in str(to_track.get("source") or "").lower():
    if is_english:
      return (
        f"Let's turn the corner gently here, just enough to let a new color into the set. "
        f"{from_title} gave us a place to stand, so this does not need to feel like being pushed into a different room. "
        f"After that, {to_artist}'s {to_title} brings in a small change of light and gives us something fresh to follow.",
        f"Turning the mood toward {to_title} with a new color.",
      )
    return (
      f"怎么说呢，这里可以稍微拐个弯。《{from_title}》之后，试试 {to_artist} 的《{to_title}》，会有一点新的颜色。",
      f"从刚才的气氛拐个弯，试试《{to_title}》。",
    )

  if is_english:
    templates = [
      (
        f"{from_title} opened up the {from_mood} side, and I want to let that feeling breathe for a second. "
        f"There is a nice little afterimage there, the kind that makes the next choice matter more than a quick announcement would. "
        f"Now {to_title} carries us toward something more {to_mood}, but it keeps the handoff friendly.",
        f"Moving from {from_title} toward {to_title}'s {to_mood} side.",
      ),
      (
        f"Let's keep the turn gentle here, like lowering the lights instead of changing rooms. "
        f"The last track left enough warmth behind that we can use it as a bridge, not a hard stop. "
        f"{to_title} carries that afterglow forward and gives the set a softer landing.",
        f"{to_title} carries the afterglow forward.",
      ),
      (
        f"Let's hear this from another angle before the set gets too settled. "
        f"The previous track gave us one version of the room, and this is the moment where a friend might say, try this side too. "
        f"{to_artist}'s {to_title} moves us into a more {to_mood} place without breaking the mood.",
        f"Another angle now: {to_title} moves the set toward {to_mood}.",
      ),
    ]
    return templates[index % len(templates)]

  templates = [
    (
      f"嗯，刚才《{from_title}》把{from_mood}铺开了。我们往前走一点，让《{to_title}》接住更{to_mood}的那一面。",
      f"从《{from_title}》转向《{to_title}》的{to_mood}。",
    ),
    (
      f"这一段先别切太猛。《{to_title}》会把刚才的余温接过去，像把房间里的光调暗一点。",
      f"让《{to_title}》接住刚才的余温。",
    ),
    (
      f"好，换一个角度听。{to_artist} 的《{to_title}》会把这组歌带到更{to_mood}的位置。",
      f"换个角度，听《{to_title}》的{to_mood}。",
    ),
  ]
  return templates[index % len(templates)]


def _pair_index(pair: tuple[str, str], pairs: list[tuple[str, str]]) -> int:
  try:
    return pairs.index(pair)
  except ValueError:
    return 0


def _mood_label(track: dict[str, Any]) -> str:
  mood = str(track.get("mood") or "").strip()
  if mood:
    return mood
  lane = str(track.get("sourceLane") or "").replace("_", " ").strip()
  if lane:
    return lane
  return "新的气氛"


def _same_clean_value(left: Any, right: Any) -> bool:
  left_value = str(left or "").strip().casefold()
  right_value = str(right or "").strip().casefold()
  return bool(left_value and right_value and left_value == right_value)


def mock_payload(state: AgentState) -> dict[str, Any]:
  request = state["request"]
  candidates = state.get("candidates", [])
  return {
    "items": [item.model_dump() for item in mock_items(request, candidates)],
  }


def mock_items(request: RadioGenerateRequest, candidates: list[RadioTrack]) -> list[RadioGeneratedItem]:
  liked = set(request.memory.likedTrackKeys)
  skipped = set(request.memory.skippedTrackKeys)
  disliked = set(request.memory.dislikedTrackKeys)
  recent = {key: index for index, key in enumerate(request.memory.recentlyPlayedTrackKeys)}

  def score(track: RadioTrack) -> float:
    value = 62.0 if track.playlistName else 44.0
    if track.radioIdentity in liked:
      value += 35
    if track.radioIdentity in skipped:
      value -= 18
    if track.radioIdentity in disliked:
      value -= 120
    if track.radioIdentity in recent:
      value -= max(8, 28 - recent[track.radioIdentity] * 4)
    if track.duration:
      value += max(0, 8 - abs(track.duration - 210) / 30)
    if not track.playlistName:
      value += (1 - request.tuning.familiarity) * 18
    return round(value, 2)

  ranked = sorted(candidates, key=lambda track: (-score(track), track.artist.lower(), track.title.lower()))
  distributed = distribute_artists(ranked)
  items: list[RadioGeneratedItem] = []
  for index, track in enumerate(distributed[: request.limit]):
    source = "playlist" if track.playlistName else "catalog"
    items.append(
      RadioGeneratedItem(
        radioIdentity=track.radioIdentity,
        reason=mock_reason(track, source, index),
        role=role_for_index(index, request.limit, source),
        score=score(track),
        source=source,
      )
    )
  return items


def distribute_artists(tracks: list[RadioTrack]) -> list[RadioTrack]:
  remaining = list(tracks)
  result: list[RadioTrack] = []
  previous_artist: str | None = None

  while remaining:
    index = next(
      (idx for idx, track in enumerate(remaining) if track.artist.casefold() != previous_artist),
      0,
    )
    track = remaining.pop(index)
    result.append(track)
    previous_artist = track.artist.casefold()

  return result


def item_from_raw(track: RadioTrack, raw_item: dict[str, Any], index: int) -> RadioGeneratedItem:
  source = str(raw_item.get("source") or ("playlist" if track.playlistName else "catalog"))
  fallback_score = max(1, 90 - index * 3)
  return RadioGeneratedItem(
    radioIdentity=track.radioIdentity,
    reason=str(raw_item.get("reason") or mock_reason(track, source, index)),
    role=str(raw_item.get("role") or role_for_index(index, 14, source)),
    score=coerce_score(raw_item.get("score"), fallback_score),
    source=source,
  )


def coerce_score(value: Any, fallback: float) -> float:
  try:
    score = float(value)
  except (TypeError, ValueError):
    return float(fallback)

  if not math.isfinite(score):
    return float(fallback)
  return score


def default_intro(request: RadioGenerateRequest) -> str:
  playlist_names = sorted({track.playlistName for track in request.seedTracks if track.playlistName})
  if _is_english(request):
    if len(playlist_names) == 1:
      return (
        f"We're tuned from {playlist_names[0]}, so the first part can stay close to something familiar. "
        "I'll leave a little room for discovery without pulling the set too far away."
      )
    if len(playlist_names) > 1:
      return (
        f"I'm blending {len(playlist_names)} playlists into one personal radio set. "
        "We'll keep the handoff gentle, like a friend sorting through records beside you."
      )
    return (
      "Airset is shaping a personal radio set from your current music seeds. "
      "I'll keep it warm and specific, with a little space for a good surprise."
    )

  if len(playlist_names) == 1:
    return f"从 {playlist_names[0]} 调出这一段，留一点发现新歌的空间。"
  if len(playlist_names) > 1:
    return f"正在把 {len(playlist_names)} 个歌单混成一段私人电台。"
  return "Airset 正在根据你当前的音乐种子整理一段私人电台。"


def mock_reason(track: RadioTrack, source: str, index: int) -> str:
  if source == "playlist" and track.playlistName:
    return f"Pulled from {track.playlistName} as a familiar anchor for this set."
  if index == 0:
    return f"Opens the set with {track.artist}'s lane and a clear signal."
  return f"Matched near {track.artist} and the {track.mood or 'Apple Music'} thread."


def role_for_index(index: int, limit: int, source: str) -> str:
  if index == 0:
    return "opener"
  if index >= max(0, limit - 1):
    return "closer"
  if source == "catalog":
    return "discovery"
  return "anchor" if index % 3 == 0 else "bridge"


def _is_english(request: RadioGenerateRequest) -> bool:
  return request.speechLanguage.lower().startswith("en")
