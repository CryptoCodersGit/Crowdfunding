# Crypto Coders | Solidity Crowdfunding Platform

قرارداد هوشمند پلتفرم جذب سرمایه جمعی (Crowdfunding) به زبان Solidity با مکانیزم بررسی کمپین توسط ادمین، کارمزد پلتفرم و استرداد امن وجه.

## ساختار فایل‌ها و قرارداد

| فایل | نام قرارداد | نسخه کامپایلر | توضیحات |
|---|---|---|---|
| `CrowdfundingPlatform.sol` | `CrowdfundingPlatform` | `^0.8.24` | ایجاد کمپین، تأیید/رد توسط ادمین، مشارکت با ETH، تسویه کمپین‌های موفق (کسر ۲٪ کارمزد) و استرداد کمپین‌های ناموفق |

## وضعیت‌های کمپین (`enum CampaignStatus`)
- `Pending`: در انتظار بررسی ادمین
- `Active`: تأییدشده و در حال جذب سرمایه
- `Rejected`: ردشده توسط ادمین
- `Successful`: رسیده به هدف مالی (`totalRaised >= goal`) پس از پایان مهلت
- `Failed`: نرسیده به هدف مالی پس از پایان مهلت
- `Cancelled`: لغوشده توسط سازنده (قبل از جذب هرگونه مشارکت)
- `Settled`: تسویه‌شده با سازنده کمپین

## توابع اصلی
- `createCampaign(string title, string metadataURI, uint256 goal, uint256 durationDays)`: ثبت کمپین جدید با مدت ۱ تا ۳۰ روز
- `reviewCampaign(uint256 campaignId, bool approved)`: تأیید یا رد کمپین توسط مالک پلتفرم (`onlyOwner`)
- `contribute(uint256 campaignId) payable`: مشارکت مالی با ETH در کمپین‌های فعال قبل از `deadline`
- `finalizeCampaign(uint256 campaignId)`: تعیین وضعیت نهایی (`Successful` یا `Failed`) پس از پایان مهلت زمانی
- `claimFunds(uint256 campaignId)`: برداشت وجه توسط سازنده کمپین موفق (۹۸٪ سازنده و ۲٪ کارمزد پلتفرم بر اساس `PLATFORM_FEE_BPS = 200`)
- `refund(uint256 campaignId)`: بازپس‌گیری وجه توسط مشارکت‌کنندگان در صورت `Failed` شدن کمپین
- `cancelCampaign(uint256 campaignId)`: لغو کمپین بدون مشارکت توسط سازنده
