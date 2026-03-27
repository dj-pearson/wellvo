package net.wellvo.android.data.models

import androidx.compose.ui.graphics.Color

val MoodHappy = Color(0xFF22C55E)
val MoodNeutral = Color(0xFFF59E0B)
val MoodTired = Color(0xFF6B7280)
val MoodExcited = Color(0xFFF97316)
val MoodBored = Color(0xFF8B5CF6)
val MoodHungry = Color(0xFFEF4444)
val MoodScared = Color(0xFF3B82F6)
val MoodHavingFun = Color(0xFFEC4899)

val KidResponsePickUp = Color(0xFF3B82F6)
val KidResponseStayLonger = Color(0xFF22C55E)
val KidResponseSos = Color(0xFFEF4444)

fun Mood.emoji(): String = when (this) {
    Mood.Happy -> "\uD83D\uDE0A"
    Mood.Neutral -> "\uD83D\uDE10"
    Mood.Tired -> "\uD83D\uDE34"
    Mood.Excited -> "\uD83E\uDD29"
    Mood.Bored -> "\uD83D\uDE12"
    Mood.Hungry -> "\uD83C\uDF55"
    Mood.Scared -> "\uD83D\uDE30"
    Mood.HavingFun -> "\uD83C\uDF89"
}

fun Mood.displayName(): String = when (this) {
    Mood.Happy -> "Good"
    Mood.Neutral -> "Okay"
    Mood.Tired -> "Tired"
    Mood.Excited -> "Excited"
    Mood.Bored -> "Bored"
    Mood.Hungry -> "Hungry"
    Mood.Scared -> "Scared"
    Mood.HavingFun -> "Having Fun"
}

fun Mood.color(): Color = when (this) {
    Mood.Happy -> MoodHappy
    Mood.Neutral -> MoodNeutral
    Mood.Tired -> MoodTired
    Mood.Excited -> MoodExcited
    Mood.Bored -> MoodBored
    Mood.Hungry -> MoodHungry
    Mood.Scared -> MoodScared
    Mood.HavingFun -> MoodHavingFun
}

fun Mood.isStandardMood(): Boolean = this in listOf(Mood.Happy, Mood.Neutral, Mood.Tired)

enum class LocationLabel(val displayName: String, val icon: String) {
    Home("Home", "home"),
    School("School", "school"),
    FriendsHouse("Friend's House", "people"),
    Park("Park", "park"),
    Store("Store", "shopping_cart"),
    Other("Other", "location_on");

    companion object {
        fun fromSerialName(name: String): LocationLabel? = when (name) {
            "home" -> Home
            "school" -> School
            "friends_house" -> FriendsHouse
            "park" -> Park
            "store" -> Store
            "other" -> Other
            else -> null
        }
    }

    val serialName: String
        get() = when (this) {
            Home -> "home"
            School -> "school"
            FriendsHouse -> "friends_house"
            Park -> "park"
            Store -> "store"
            Other -> "other"
        }
}

enum class KidResponseType(val label: String, val icon: String, val color: Color) {
    PickingMeUp("Pick me up!", "directions_car", KidResponsePickUp),
    CanStayLonger("Can I stay longer?", "schedule", KidResponseStayLonger),
    Sos("SOS!", "warning", KidResponseSos);

    companion object {
        fun fromSerialName(name: String): KidResponseType? = when (name) {
            "picking_me_up" -> PickingMeUp
            "can_stay_longer" -> CanStayLonger
            "sos" -> Sos
            else -> null
        }
    }

    val serialName: String
        get() = when (this) {
            PickingMeUp -> "picking_me_up"
            CanStayLonger -> "can_stay_longer"
            Sos -> "sos"
        }
}
