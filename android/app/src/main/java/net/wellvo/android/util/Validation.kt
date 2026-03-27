package net.wellvo.android.util

object Validation {
    fun isValidEmail(email: String): Boolean {
        return email.matches(Regex("^[A-Za-z0-9+_.-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"))
    }

    fun isValidPassword(password: String): Boolean {
        return password.length >= 8 &&
                password.any { it.isUpperCase() } &&
                password.any { it.isLowerCase() } &&
                password.any { it.isDigit() }
    }

    fun passwordErrors(password: String): String? {
        return when {
            password.length < 8 -> "Password must be at least 8 characters."
            !password.any { it.isUpperCase() } -> "Password must contain an uppercase letter."
            !password.any { it.isLowerCase() } -> "Password must contain a lowercase letter."
            !password.any { it.isDigit() } -> "Password must contain a number."
            else -> null
        }
    }

    fun isValidDisplayName(name: String): Boolean {
        return name.length in 2..50
    }

    fun displayNameError(name: String): String? {
        return when {
            name.length < 2 -> "Name must be at least 2 characters."
            name.length > 50 -> "Name must be 50 characters or less."
            else -> null
        }
    }
}
