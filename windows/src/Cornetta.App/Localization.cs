using System;

namespace Cornetta.App
{
    internal enum AppLanguage
    {
        Italian,
        English
    }

    /// <summary>Interface language saved in HKCU\Software\Cornetta.</summary>
    internal static class AppLanguageSettings
    {
        private static AppLanguage? current;

        public static event Action? LanguageChanged;

        public static AppLanguage Current
        {
            get
            {
                if (current.HasValue) return current.Value;
                current = Resolve(Settings.Language);
                Settings.Language = Raw(current.Value);
                return current.Value;
            }
        }

        public static void Select(AppLanguage language)
        {
            if (Current == language) return;
            current = language;
            Settings.Language = Raw(language);
            LanguageChanged?.Invoke();
        }

        internal static AppLanguage Resolve(string saved)
        {
            if (saved == "en") return AppLanguage.English;
            if (saved == "it") return AppLanguage.Italian;
            return AppLanguage.English;
        }

        private static string Raw(AppLanguage language) => language == AppLanguage.English ? "en" : "it";
    }
}
