-- Example rows only (not applied automatically). Shows how to fill the knowledge table.
-- After changing rows via SQL you do not need to do anything else: search_text is generated.
insert into public.knowledge (question, answer, keywords, category) values
('هر چند وقت یک بار باید ضدآفتاب بزنم؟',
 'نمونه: ضدآفتاب را حدود هر دو تا سه ساعت یک بار در معرض آفتاب تجدید کنید.',
 'ضدآفتاب ضد آفتاب SPF تجدید',
 'ضدآفتاب'),
('چرا پوستم بعد از شستشو کشیده می‌شود؟',
 'نمونه: کشیدگی بعد از شستشو معمولاً نشانه‌ی خشکی یا شوینده‌ی قوی است.',
 'خشکی پوست کشیدگی شوینده',
 'شستشو');
