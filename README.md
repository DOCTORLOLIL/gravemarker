# Grave Marker – אפליקציה

אפליקציית Flutter לאיתור קברים וניווט עד הקבר. משתמשת באותו Supabase (פרויקט kever) כמו האתר gravemarker.bulu.ltd.

- כל דחיפה ל-main בונה APK ב-GitHub Actions. הקובץ להורדה: Releases → "גרסת בדיקה".
- הרצה מקומית: `flutter create --platforms=android --org ltd.bulu --project-name gravemarker .` פעם אחת, ואז `python tool/patch_android.py` ו-`flutter run`.
