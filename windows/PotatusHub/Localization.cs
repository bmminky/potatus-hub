using System.Globalization;

namespace PotatusHub;

public static class L
{
    public enum Language
    {
        System,
        Korean,
        English,
        Japanese,
        Chinese,
    }

    public static Language Preference
    {
        get => AppSettings.Current.Language;
        set
        {
            AppSettings.Current.Language = value;
            AppSettings.Save();
        }
    }

    public static Language Resolved
    {
        get
        {
            if (Preference != Language.System) return Preference;
            var code = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
            return code switch
            {
                "ko" => Language.Korean,
                "ja" => Language.Japanese,
                "zh" => Language.Chinese,
                _ => Language.English,
            };
        }
    }

    public static string T(string ko, string en, string ja, string zh) => Resolved switch
    {
        Language.Korean => ko,
        Language.Japanese => ja,
        Language.Chinese => zh,
        _ => en,
    };
}
