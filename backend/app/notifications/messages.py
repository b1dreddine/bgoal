"""Localized notification texts (en, fr, ar)."""
from app.domain import Duration, EventType, Match, MatchEvent, Team
from app.notifications.diff import Kind, Notice

T = {
    "en": {
        Kind.STARTING_SOON: ("⏰ Starting soon: {home} vs {away}", "Kick-off in {mins} minutes · {comp}"),
        Kind.KICKOFF: ("▶️ Kick-off: {home} vs {away}", "{comp}"),
        Kind.GOAL: ("⚽ GOAL! {home} {sh}–{sa} {away}{scorer}", "{extra}{comp}"),
        Kind.GOAL_DISALLOWED: ("❌ Goal disallowed: {home} {sh}–{sa} {away}", "VAR decision · {comp}"),
        Kind.RED_CARD: ("🟥 Red card: {player} ({team}){minute}", "{home} {sh}–{sa} {away} · {comp}"),
        Kind.HALF_TIME: ("⏸ Half-time: {home} {sh}–{sa} {away}", "{comp}"),
        Kind.FULL_TIME: ("🏁 Full-time: {home} {sh}–{sa} {away}{suffix}", "{comp}"),
        Kind.POSTPONED: ("📅 Postponed: {home} vs {away}", "{comp}"),
        Kind.ABANDONED: ("⚠️ Abandoned: {home} {sh}–{sa} {away}", "{comp}"),
        Kind.CANCELLED: ("🚫 Cancelled: {home} vs {away}", "{comp}"),
        "assist": "Assist: {name} · ",
        "pen": "Penalty · ",
        "og": "Own goal · ",
        "aet": " (AET)",
        "pens": " — {team} win {ph}–{pa} on penalties",
        "player": "Player",
    },
    "fr": {
        Kind.STARTING_SOON: ("⏰ Bientôt : {home} – {away}", "Coup d'envoi dans {mins} minutes · {comp}"),
        Kind.KICKOFF: ("▶️ Coup d'envoi : {home} – {away}", "{comp}"),
        Kind.GOAL: ("⚽ BUT ! {home} {sh}–{sa} {away}{scorer}", "{extra}{comp}"),
        Kind.GOAL_DISALLOWED: ("❌ But refusé : {home} {sh}–{sa} {away}", "Décision VAR · {comp}"),
        Kind.RED_CARD: ("🟥 Carton rouge : {player} ({team}){minute}", "{home} {sh}–{sa} {away} · {comp}"),
        Kind.HALF_TIME: ("⏸ Mi-temps : {home} {sh}–{sa} {away}", "{comp}"),
        Kind.FULL_TIME: ("🏁 Fin du match : {home} {sh}–{sa} {away}{suffix}", "{comp}"),
        Kind.POSTPONED: ("📅 Reporté : {home} – {away}", "{comp}"),
        Kind.ABANDONED: ("⚠️ Arrêté : {home} {sh}–{sa} {away}", "{comp}"),
        Kind.CANCELLED: ("🚫 Annulé : {home} – {away}", "{comp}"),
        "assist": "Passe décisive : {name} · ",
        "pen": "Penalty · ",
        "og": "Contre son camp · ",
        "aet": " (a.p.)",
        "pens": " — {team} s'impose {ph}–{pa} aux tirs au but",
        "player": "Joueur",
    },
    "ar": {
        Kind.STARTING_SOON: ("⏰ قريبًا: {home} ضد {away}", "انطلاق المباراة خلال {mins} دقيقة · {comp}"),
        Kind.KICKOFF: ("▶️ انطلاق المباراة: {home} ضد {away}", "{comp}"),
        Kind.GOAL: ("⚽ هدف! {home} {sh}–{sa} {away}{scorer}", "{extra}{comp}"),
        Kind.GOAL_DISALLOWED: ("❌ هدف ملغى: {home} {sh}–{sa} {away}", "قرار حكم الفيديو · {comp}"),
        Kind.RED_CARD: ("🟥 بطاقة حمراء: {player} ({team}){minute}", "{home} {sh}–{sa} {away} · {comp}"),
        Kind.HALF_TIME: ("⏸ نهاية الشوط الأول: {home} {sh}–{sa} {away}", "{comp}"),
        Kind.FULL_TIME: ("🏁 نهاية المباراة: {home} {sh}–{sa} {away}{suffix}", "{comp}"),
        Kind.POSTPONED: ("📅 تأجيل: {home} ضد {away}", "{comp}"),
        Kind.ABANDONED: ("⚠️ إيقاف المباراة: {home} {sh}–{sa} {away}", "{comp}"),
        Kind.CANCELLED: ("🚫 إلغاء: {home} ضد {away}", "{comp}"),
        "assist": "تمريرة حاسمة: {name} · ",
        "pen": "ركلة جزاء · ",
        "og": "هدف عكسي · ",
        "aet": " (بعد التمديد)",
        "pens": " — فوز {team} {ph}–{pa} بركلات الترجيح",
        "player": "لاعب",
    },
}


def _name(team: Team) -> str:
    return team.short_name or team.name


def _minute(ev: MatchEvent | None) -> str:
    if ev is None or ev.minute is None:
        return ""
    return f" {ev.minute}+{ev.extra_minute}'" if ev.extra_minute else f" {ev.minute}'"


def render(notice: Notice, language: str) -> tuple[str, str]:
    t = T.get(language, T["en"])
    m: Match = notice.match
    sh, sa = notice.score or (m.score.home or 0, m.score.away or 0)
    ev = notice.event
    fields = {
        "home": _name(m.home), "away": _name(m.away), "sh": sh, "sa": sa, "comp": m.competition.name,
        "mins": notice.minutes_to_kickoff or 15,"scorer": "", "extra": "", "player": "", "team": "", "minute": _minute(ev), "suffix": "",
    }
    if notice.kind == Kind.GOAL and ev is not None:
        if ev.player_name:
            fields["scorer"] = f" — {ev.player_name}{_minute(ev)}"
        if ev.type == EventType.PENALTY_GOAL:
            fields["extra"] = t["pen"]
        elif ev.type == EventType.OWN_GOAL:
            fields["extra"] = t["og"]
        elif ev.related_player_name:
            fields["extra"] = t["assist"].format(name=ev.related_player_name)
    if notice.kind == Kind.RED_CARD:
        fields["player"] = (ev.player_name if ev else None) or t["player"]
        fields["team"] = _name(m.home) if notice.team_id == m.home.id else _name(m.away)
    if notice.kind == Kind.FULL_TIME:
        if m.score.duration == Duration.PENALTIES and m.score.pen_home is not None:
            winner = m.home if m.score.pen_home > m.score.pen_away else m.away
            fields["suffix"] = t["pens"].format(team=_name(winner), ph=m.score.pen_home, pa=m.score.pen_away)
        elif m.score.duration == Duration.EXTRA_TIME:
            fields["suffix"] = t["aet"]
    title, body = t[notice.kind]
    return title.format(**fields), body.format(**fields)
