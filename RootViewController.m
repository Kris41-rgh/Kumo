#import "RootViewController.h"
#import <QuartzCore/QuartzCore.h>
#import <CoreLocation/CoreLocation.h>

// погода: wttr.in, ключ не нужен
#define API_BASE @"http://wttr.in/"
#define GEO_BASE @"http://geocoding-api.open-meteo.com/v1/search"
#define DEF_LAT 48.4647
#define DEF_LON 35.0462
#define DEF_CITY @"Днепр"
#define CAT_SCALE 0.5   // размер котиков: меньше число = меньше котики
#define CAT_RATE 0.5    // сколько котиков: меньше число = реже
#define TOP_H 316       // высота верхней части настроек
#define CITY_Y 270      // где начинается блок городов в настройках

// типы: 0 ясно, 1 облачно, 2 туман, 3 дождь, 4 снег, 5 гроза
static NSString *ICON[] = {@"\u2600", @"\u26C5", @"\U0001F301", @"\u2614", @"\u26C4", @"\u26A1"};
static NSString *NAME[] = {@"Ясно", @"Облачно", @"Туман", @"Дождь", @"Снег", @"Гроза"};
// верх фона, низ фона, акцент круга (цвета по погоде)
static const CGFloat P[6][9] = {
    {.32,.20,.12, .13,.10,.11, 1.0,.60,.25},
    {.22,.25,.31, .11,.12,.15, .50,.62,.85},
    {.26,.26,.28, .12,.12,.13, .68,.70,.75},
    {.12,.17,.26, .07,.09,.14, .28,.52,.95},
    {.22,.26,.33, .10,.12,.16, .72,.86,1.0},
    {.20,.13,.28, .08,.06,.13, .68,.42,.95}};
// темы: коралл, океан, лес, фиалка
static const CGFloat TH[4][9] = {
    {.30,.14,.15, .12,.09,.10, .96,.36,.45},
    {.07,.20,.32, .04,.09,.16, .25,.65,.90},
    {.10,.25,.17, .05,.11,.08, .35,.80,.50},
    {.22,.14,.34, .09,.06,.15, .70,.50,.95}};

// палитра акцентов: коралл, оранжевый, зелёный, бирюзовый, синий, фиолетовый, розовый
static const CGFloat PAL[7][3] = {{.96,.36,.45},{1.0,.62,.25},{.35,.80,.50},{.20,.75,.75},{.25,.65,.90},{.70,.50,.95},{.95,.45,.80}};

static UIColor *C(const CGFloat *p) { return [UIColor colorWithRed:p[0] green:p[1] blue:p[2] alpha:1]; }

static UILabel *L(CGRect f, CGFloat sz, BOOL bold, CGFloat a) {
    UILabel *l = [[UILabel alloc] initWithFrame:f];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [UIColor colorWithWhite:1 alpha:a];
    l.font = bold ? [UIFont boldSystemFontOfSize:sz] : [UIFont systemFontOfSize:sz];
    l.textAlignment = NSTextAlignmentCenter;
    return l;
}

@interface RootViewController () <CLLocationManagerDelegate, NSURLConnectionDataDelegate,
    UIGestureRecognizerDelegate, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate> {
    CAGradientLayer *bg;
    CAEmitterLayer *emitter;
    UIView *content, *circle, *card, *settings;
    UILabel *tempL, *iconL, *cityL, *subL, *descL;
    UIPageControl *pc;
    NSMutableArray *vals, *caps, *swatches;
    UITableView *tbl;
    UITextField *field;
    UIView *topBox, *cityBox;
    UILabel *hintL;
    NSArray *sugs;
    NSString *lastQuery;
    UISegmentedControl *styleSeg;
    UISwitch *tipSw;
    UILabel *tipL;
    CAGradientLayer *gloss;
    UIColor *accent;
    int style;
    BOOL tips, light;
    float hue;
    UIScrollView *sc;
    UISegmentedControl *modeSeg;
    UISlider *hueSl;
    UIColor *ink, *bgTop, *bgBot;
    UISwitch *catSw, *fSw;
    CLLocationManager *lm;
    NSMutableArray *cities;
    NSMutableDictionary *cache;
    NSDictionary *data;
    NSMutableData *buf;
    NSURLConnection *conn;
    NSString *loadingKey;
    NSUserDefaults *ud;
    int idx, theme, lastType;
    BOOL showForecast, cats, fahr;
}
@end

@implementation RootViewController

#pragma mark - prefs

- (void)loadPrefs {
    ud = [NSUserDefaults standardUserDefaults];
    theme = (int)[ud integerForKey:@"theme"];
    cats = [ud objectForKey:@"cats"] ? [ud boolForKey:@"cats"] : YES;
    fahr = [ud boolForKey:@"fahr"];
    style = (int)[ud integerForKey:@"style"];
    light = [ud boolForKey:@"light"];
    hue = [ud objectForKey:@"hue"] ? [ud floatForKey:@"hue"] : 0.55f;
    ink = light ? [UIColor colorWithRed:.12 green:.14 blue:.20 alpha:1] : [UIColor whiteColor];
    tips = [ud objectForKey:@"tips"] ? [ud boolForKey:@"tips"] : YES;
    accent = C(P[1] + 6);
    cities = [NSMutableArray array];
    [cities addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
        DEF_CITY, @"name", @(DEF_LAT), @"lat", @(DEF_LON), @"lon", nil]];
    for (NSDictionary *d in [ud arrayForKey:@"cities"])
        [cities addObject:[NSMutableDictionary dictionaryWithDictionary:d]];
    cache = [NSMutableDictionary dictionary];
}

- (void)saveCities {
    NSArray *ex = cities.count > 1 ? [cities subarrayWithRange:NSMakeRange(1, cities.count - 1)] : @[];
    [ud setObject:ex forKey:@"cities"];
    [ud synchronize];
}

- (NSString *)keyForCity:(NSDictionary *)c {
    return [NSString stringWithFormat:@"%.3f,%.3f", [c[@"lat"] doubleValue], [c[@"lon"] doubleValue]];
}

- (long)T:(double)c { return lround(fahr ? c * 9.0 / 5.0 + 32 : c); }

#pragma mark - UI

- (UIView *)roundBtn:(CGRect)f action:(SEL)s inView:(UIView *)parent {
    UIView *v = [[UIView alloc] initWithFrame:f];
    v.backgroundColor = [UIColor colorWithWhite:1 alpha:.15];
    v.layer.cornerRadius = f.size.width / 2;
    v.tag = 715;
    v.layer.borderWidth = 1;
    v.layer.borderColor = [UIColor colorWithWhite:1 alpha:.12].CGColor;
    [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:s]];
    [parent addSubview:v];
    return v;
}

- (UILabel *)caption:(NSString *)t y:(CGFloat)y inView:(UIView *)p {
    UILabel *l = L(CGRectMake(20, y, 200, 16), 11, YES, .5);
    l.textAlignment = NSTextAlignmentLeft;
    l.text = t;
    [p addSubview:l];
    return l;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self loadPrefs];
    CGRect b = self.view.bounds;
    CGFloat w = b.size.width, h = b.size.height;

    bg = [CAGradientLayer layer];
    bg.frame = b;
    bg.colors = @[(id)C(P[1]).CGColor, (id)C(P[1] + 3).CGColor];
    [self.view.layer addSublayer:bg];

    content = [[UIView alloc] initWithFrame:b];
    [self.view addSubview:content];

    cityL = L(CGRectMake(60, 14, w - 120, 30), 26, YES, 1);
    subL = L(CGRectMake(50, 44, w - 100, 18), 13, NO, .6);
    [content addSubview:cityL];
    [content addSubview:subL];

    pc = [[UIPageControl alloc] initWithFrame:CGRectMake(0, 64, w, 14)];
    pc.userInteractionEnabled = NO;
    [self.view addSubview:pc];

    // левая кнопка: настройки (два ползунка)
    UIView *lb = [self roundBtn:CGRectMake(14, 12, 40, 40) action:@selector(openSettings) inView:self.view];
    for (int i = 0; i < 2; i++) {
        UIView *ln = [[UIView alloc] initWithFrame:CGRectMake(11, 14 + i * 10, 18, 2)];
        ln.backgroundColor = [UIColor whiteColor]; ln.layer.cornerRadius = 1; ln.tag = 900;
        [lb addSubview:ln];
        UIView *kn = [[UIView alloc] initWithFrame:CGRectMake(i ? 10 : 20, 11 + i * 10, 8, 8)];
        kn.backgroundColor = [UIColor whiteColor]; kn.layer.cornerRadius = 4; kn.tag = 900;
        [lb addSubview:kn];
    }

    // правая кнопка: прогноз (три столбика)
    UIView *rb = [self roundBtn:CGRectMake(w - 54, 12, 40, 40) action:@selector(toggle) inView:self.view];
    CGFloat hs[3] = {8, 14, 20};
    for (int i = 0; i < 3; i++) {
        UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(11 + i * 7, 29 - hs[i], 4, hs[i])];
        bar.backgroundColor = [UIColor whiteColor]; bar.layer.cornerRadius = 2; bar.tag = 900;
        [rb addSubview:bar];
    }

    // большой круг
    circle = [[UIView alloc] initWithFrame:CGRectMake((w - 180) / 2, h * 0.21, 180, 180)];
    circle.layer.cornerRadius = 90;
    circle.backgroundColor = C(P[1] + 6);
    circle.layer.shadowColor = C(P[1] + 6).CGColor;
    circle.layer.shadowOpacity = .7; circle.layer.shadowRadius = 26;
    circle.layer.shadowOffset = CGSizeZero;
    gloss = [CAGradientLayer layer];
    CAGradientLayer *gl = gloss;
    gl.frame = circle.bounds; gl.cornerRadius = 90;
    gl.colors = @[(id)[UIColor colorWithWhite:1 alpha:.28].CGColor, (id)[UIColor colorWithWhite:1 alpha:0].CGColor];
    [circle.layer addSublayer:gl];
    iconL = L(CGRectMake(0, 22, 180, 50), 38, NO, 1);
    tempL = L(CGRectMake(0, 68, 180, 76), 66, YES, 1);
    [circle addSubview:iconL];
    [circle addSubview:tempL];
    [circle addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(refresh)]];
    [content addSubview:circle];

    descL = L(CGRectMake(0, CGRectGetMaxY(circle.frame) + 16, w, 24), 18, YES, .95);
    [content addSubview:descL];
    tipL = L(CGRectMake(20, CGRectGetMaxY(circle.frame) + 42, w - 40, 18), 14, NO, .7);
    [content addSubview:tipL];

    // стеклянная карточка
    card = [[UIView alloc] initWithFrame:CGRectMake(20, h - 112, w - 40, 96)];
    card.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
    card.layer.cornerRadius = 20;
    card.tag = 712;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:.1].CGColor;
    [content addSubview:card];
    vals = [NSMutableArray array]; caps = [NSMutableArray array];
    CGFloat cw = card.bounds.size.width / 3;
    for (int i = 0; i < 3; i++) {
        UILabel *v = L(CGRectMake(i * cw, 20, cw, 30), 22, YES, 1);
        UILabel *k = L(CGRectMake(i * cw, 54, cw, 18), 12, NO, .55);
        [card addSubview:v]; [card addSubview:k];
        [vals addObject:v]; [caps addObject:k];
    }

    // котики и частицы поверх контента
    emitter = [CAEmitterLayer layer];
    emitter.frame = b;
    [self.view.layer insertSublayer:emitter above:bg];   // котики на заднем плане

    // свайпы между городами
    UISwipeGestureRecognizer *sl = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipe:)];
    sl.direction = UISwipeGestureRecognizerDirectionLeft; sl.delegate = self;
    UISwipeGestureRecognizer *sr = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipe:)];
    sr.direction = UISwipeGestureRecognizerDirectionRight; sr.delegate = self;
    [self.view addGestureRecognizer:sl];
    [self.view addGestureRecognizer:sr];

    [self buildSettings];

    [self applyMode];
    [self applyStyle];

    lm = [[CLLocationManager alloc] init];
    lm.delegate = self;
    lm.desiredAccuracy = kCLLocationAccuracyKilometer;
    [self showCity];
    [self locate];
}

#pragma mark - settings screen

- (UISwitch *)switchRow:(NSString *)title y:(CGFloat)y on:(BOOL)on action:(SEL)act {
    CGFloat w = self.view.bounds.size.width;
    UILabel *l = L(CGRectMake(20, y, 220, 30), 16, NO, .95);
    l.textAlignment = NSTextAlignmentLeft; l.text = title;
    [topBox addSubview:l];
    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(w - 20 - 79, y + 1, 79, 27)];
    sw.on = on;
    [sw addTarget:self action:act forControlEvents:UIControlEventValueChanged];
    [topBox addSubview:sw];
    return sw;
}

- (UIImage *)solid:(UIColor *)c size:(CGSize)sz {
    UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
    [c setFill];
    UIRectFill(CGRectMake(0, 0, sz.width, sz.height));
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

- (UIImage *)thumbImage {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(26, 26), NO, 0);
    CGContextRef g = UIGraphicsGetCurrentContext();
    CGContextSetShadowWithColor(g, CGSizeMake(0, 1), 3, [UIColor colorWithWhite:0 alpha:.45].CGColor);
    [[UIColor whiteColor] setFill];
    CGContextFillEllipseInRect(g, CGRectMake(3, 3, 20, 20));
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

- (void)buildSettings {
    CGRect b = self.view.bounds;
    CGFloat w = b.size.width, h = b.size.height;
    settings = [[UIView alloc] initWithFrame:b];
    settings.hidden = YES;
    [self.view addSubview:settings];
    sugs = @[];

    sc = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 56, w, h - 56)];
    sc.showsVerticalScrollIndicator = NO;
    [settings addSubview:sc];

    topBox = [[UIView alloc] initWithFrame:CGRectMake(0, 0, w, TOP_H)];
    [sc addSubview:topBox];

    // тёмная / светлая
    [self caption:@"ОФОРМЛЕНИЕ" y:0 inView:topBox];
    modeSeg = [[UISegmentedControl alloc] initWithItems:@[@"Тёмная", @"Светлая"]];
    modeSeg.frame = CGRectMake(20, 18, w - 40, 30);
    modeSeg.segmentedControlStyle = UISegmentedControlStyleBar;
    modeSeg.selectedSegmentIndex = light ? 1 : 0;
    [modeSeg addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [topBox addSubview:modeSeg];

    // палитра: «A» (по погоде) + 7 цветов + ползунок оттенка
    [self caption:@"ЦВЕТ" y:60 inView:topBox];
    swatches = [NSMutableArray array];
    CGFloat gap = (w - 40 - 8 * 30) / 7.0;
    for (int i = 0; i < 8; i++) {
        UIButton *sw = [UIButton buttonWithType:UIButtonTypeCustom];
        sw.frame = CGRectMake(20 + i * (30 + gap), 78, 30, 30);
        sw.layer.cornerRadius = 15;
        sw.tag = i;
        if (i == 0) {
            [sw setTitle:@"A" forState:UIControlStateNormal];
            sw.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        } else {
            sw.backgroundColor = C(PAL[i - 1]);
        }
        [sw addTarget:self action:@selector(pickTheme:) forControlEvents:UIControlEventTouchUpInside];
        [topBox addSubview:sw];
        [swatches addObject:sw];
    }
    UIView *rbar = [[UIView alloc] initWithFrame:CGRectMake(24, 122, w - 48, 10)];
    rbar.layer.cornerRadius = 5; rbar.layer.masksToBounds = YES;
    CAGradientLayer *rg = [CAGradientLayer layer];
    rg.frame = rbar.bounds;
    NSMutableArray *cols = [NSMutableArray array];
    for (int i = 0; i <= 12; i++)
        [cols addObject:(id)[UIColor colorWithHue:i / 12.0 saturation:.62 brightness:.95 alpha:1].CGColor];
    rg.colors = cols;
    rg.startPoint = CGPointMake(0, .5); rg.endPoint = CGPointMake(1, .5);
    [rbar.layer addSublayer:rg];
    [topBox addSubview:rbar];
    hueSl = [[UISlider alloc] initWithFrame:CGRectMake(20, 114, w - 40, 26)];
    UIImage *clear = [self solid:[UIColor clearColor] size:CGSizeMake(1, 1)];
    [hueSl setMinimumTrackImage:clear forState:UIControlStateNormal];
    [hueSl setMaximumTrackImage:clear forState:UIControlStateNormal];
    [hueSl setThumbImage:[self thumbImage] forState:UIControlStateNormal];
    hueSl.minimumValue = 0; hueSl.maximumValue = 1; hueSl.value = hue;
    [hueSl addTarget:self action:@selector(hueChanged:) forControlEvents:UIControlEventValueChanged];
    [topBox addSubview:hueSl];
    [self updateSwatches];

    // вид
    [self caption:@"ВИД" y:150 inView:topBox];
    styleSeg = [[UISegmentedControl alloc] initWithItems:@[@"Круг", @"Минимал", @"Панель"]];
    styleSeg.frame = CGRectMake(20, 168, w - 40, 30);
    styleSeg.segmentedControlStyle = UISegmentedControlStyleBar;
    styleSeg.selectedSegmentIndex = style;
    [styleSeg addTarget:self action:@selector(styleChanged) forControlEvents:UIControlEventValueChanged];
    [topBox addSubview:styleSeg];

    catSw = [self switchRow:@"Котики вместо осадков" y:210 on:cats action:@selector(catsChanged)];
    tipSw = [self switchRow:@"Совет дня" y:242 on:tips action:@selector(tipsChanged)];
    fSw = [self switchRow:@"Фаренгейты (\u00B0F)" y:274 on:fahr action:@selector(fahrChanged)];

    // города
    cityBox = [[UIView alloc] initWithFrame:CGRectMake(0, TOP_H, w, 300)];
    [sc addSubview:cityBox];
    [self caption:@"ГОРОДА" y:0 inView:cityBox];
    field = [[UITextField alloc] initWithFrame:CGRectMake(20, 20, w - 40 - 92, 34)];
    field.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
    field.tag = 712;
    field.layer.cornerRadius = 10;
    field.textColor = ink;
    field.placeholder = @"Добавить город…";
    field.returnKeyType = UIReturnKeyDone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.delegate = self;
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    field.leftViewMode = UITextFieldViewModeAlways;
    [field addTarget:self action:@selector(textChanged) forControlEvents:UIControlEventEditingChanged];
    [cityBox addSubview:field];
    UIView *add = [[UIView alloc] initWithFrame:CGRectMake(w - 20 - 84, 20, 84, 34)];
    add.backgroundColor = [UIColor colorWithWhite:1 alpha:.2];
    add.tag = 720;
    add.layer.cornerRadius = 10;
    UILabel *al = L(CGRectMake(0, 7, 84, 20), 14, YES, 1);
    al.text = @"Добавить";
    [add addSubview:al];
    [add addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(addTap)]];
    [cityBox addSubview:add];

    tbl = [[UITableView alloc] initWithFrame:CGRectMake(20, 62, w - 40, 100) style:UITableViewStylePlain];
    tbl.backgroundColor = [UIColor clearColor];
    tbl.separatorColor = [UIColor colorWithWhite:1 alpha:.15];
    tbl.rowHeight = 50;
    tbl.scrollEnabled = NO;          // прокручивается весь экран настроек
    tbl.dataSource = self; tbl.delegate = self;
    [cityBox addSubview:tbl];
    hintL = L(CGRectMake(20, 80, w - 40, 20), 13, NO, .5);
    hintL.hidden = YES;
    [cityBox addSubview:hintL];

    // заголовок и закрытие поверх всего
    UILabel *t = L(CGRectMake(60, 16, w - 120, 28), 22, YES, 1);
    t.text = @"Настройки";
    [settings addSubview:t];
    UIView *x = [self roundBtn:CGRectMake(w - 54, 12, 40, 40) action:@selector(closeSettings) inView:settings];
    UILabel *xl = L(CGRectMake(0, 4, 40, 32), 28, NO, 1);
    xl.text = @"\u00D7";
    [x addSubview:xl];
    [self layoutSettings];
}

- (void)layoutSettings {
    CGFloat w = settings.bounds.size.width;
    NSInteger n = [self typing] ? sugs.count : cities.count;
    CGFloat th = MAX(n, 1) * 50;
    tbl.frame = CGRectMake(20, 62, w - 40, th);
    cityBox.frame = CGRectMake(0, TOP_H, w, 62 + th + 20);
    sc.contentSize = CGSizeMake(w, MAX(TOP_H + 62 + th + 20, TOP_H + 200));
}

- (void)reloadCities {
    [tbl reloadData];
    [self layoutSettings];
}

- (void)updateSwatches {
    for (UIButton *sw in swatches) {
        sw.layer.borderWidth = (sw.tag == theme) ? 3 : 0;
        sw.layer.borderColor = ink.CGColor;
        if (sw.tag == 0) {
            sw.backgroundColor = light ? [UIColor colorWithWhite:0 alpha:.12] : [UIColor colorWithWhite:1 alpha:.2];
            [sw setTitleColor:ink forState:UIControlStateNormal];
        }
    }
}

- (void)pickTheme:(UIButton *)sw {
    theme = (int)sw.tag;
    [ud setInteger:theme forKey:@"theme"]; [ud synchronize];
    [self updateSwatches];
    [self refreshColors];
}

- (void)hueChanged:(UISlider *)sl {
    hue = sl.value;
    theme = 8;
    [ud setFloat:hue forKey:@"hue"];
    [ud setInteger:theme forKey:@"theme"];
    [self updateSwatches];
    [self refreshColors];
}

- (void)modeChanged {
    light = (modeSeg.selectedSegmentIndex == 1);
    [ud setBool:light forKey:@"light"]; [ud synchronize];
    [self applyMode];
}

- (void)catsChanged {
    cats = catSw.on;
    [ud setBool:cats forKey:@"cats"]; [ud synchronize];
    [self setParticles:lastType];
}

- (void)fahrChanged {
    fahr = fSw.on;
    [ud setBool:fahr forKey:@"fahr"]; [ud synchronize];
    if (data) [self render];
}

- (void)openSettings {
    [self reloadCities];
    sc.contentOffset = CGPointZero;
    settings.alpha = 0; settings.hidden = NO;
    [UIView animateWithDuration:0.25 animations:^{ settings.alpha = 1; }];
}

- (void)closeSettings {
    [field resignFirstResponder];
    field.text = @""; sugs = @[]; hintL.hidden = YES;
    [self reloadCities];
    [UIView animateWithDuration:0.2 animations:^{ settings.alpha = 0; }
                     completion:^(BOOL f) { settings.hidden = YES; }];
}

// при вводе блок городов поднимается над клавиатурой
- (void)textFieldDidBeginEditing:(UITextField *)tf {
    CGFloat w = settings.bounds.size.width;
    CGFloat vh = settings.bounds.size.height - 216 - 56;
    [UIView animateWithDuration:0.25 animations:^{
        sc.frame = CGRectMake(0, 56, w, vh);
        sc.contentOffset = CGPointMake(0, TOP_H);
    }];
}

- (void)textFieldDidEndEditing:(UITextField *)tf {
    CGFloat w = settings.bounds.size.width, h = settings.bounds.size.height;
    [UIView animateWithDuration:0.25 animations:^{
        sc.frame = CGRectMake(0, 56, w, h - 56);
    }];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf { [self addTap]; return YES; }

- (NSString *)query {
    return [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

// подсказки при вводе
- (void)textChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(runSearch) object:nil];
    hintL.hidden = YES;
    if ([self query].length < 2) {
        sugs = @[]; lastQuery = nil;
        [self reloadCities];
        return;
    }
    [self performSelector:@selector(runSearch) withObject:nil afterDelay:0.4];
}

- (void)runSearch { [self searchAddFirst:NO]; }

- (void)searchAddFirst:(BOOL)addFirst {
    NSString *q = [self query];
    if (q.length < 2) return;
    lastQuery = q;
    NSString *enc = [q stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString *u = [NSString stringWithFormat:@"%@?name=%@&count=6&language=ru", GEO_BASE, enc];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:u]
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:15]
                                       queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
        if (![q isEqualToString:lastQuery]) return;   // устаревший ответ
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        NSArray *res = [j isKindOfClass:[NSDictionary class]] ? j[@"results"] : nil;
        NSMutableArray *arr = [NSMutableArray array];
        if ([res isKindOfClass:[NSArray class]]) {
            for (NSDictionary *c in res) {
                if (!c[@"name"] || !c[@"latitude"] || !c[@"longitude"]) continue;
                NSMutableArray *parts = [NSMutableArray array];
                NSString *a1 = c[@"admin1"], *co = c[@"country"];
                if ([a1 isKindOfClass:[NSString class]] && a1.length && ![a1 isEqualToString:c[@"name"]]) [parts addObject:a1];
                if ([co isKindOfClass:[NSString class]] && co.length) [parts addObject:co];
                [arr addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    c[@"name"], @"name", [parts componentsJoinedByString:@", "], @"sub",
                    c[@"latitude"], @"lat", c[@"longitude"], @"lon", nil]];
            }
        }
        sugs = arr;
        [self reloadCities];
        hintL.text = e ? @"нет связи" : @"ничего не найдено";
        hintL.hidden = arr.count > 0;
        if (addFirst && arr.count) [self addCityFromDict:[arr objectAtIndex:0]];
    }];
}

- (void)addTap {
    if ([self query].length < 2) { [field resignFirstResponder]; return; }
    if (sugs.count) [self addCityFromDict:[sugs objectAtIndex:0]];
    else [self searchAddFirst:YES];
}

- (void)addCityFromDict:(NSDictionary *)d {
    NSMutableDictionary *c = [NSMutableDictionary dictionaryWithDictionary:d];
    BOOL dup = NO;
    // дубликат: тот же город или любая точка ближе ~12 км (включая "моё место")
    for (NSDictionary *e in cities) {
        double dla = fabs([e[@"lat"] doubleValue] - [c[@"lat"] doubleValue]);
        double dlo = fabs([e[@"lon"] doubleValue] - [c[@"lon"] doubleValue]);
        if (dla < 0.12 && dlo < 0.12) dup = YES;
    }
    if (!dup) {
        [cities addObject:c];
        [self saveCities];
    }
    field.text = @""; sugs = @[]; lastQuery = nil; hintL.hidden = YES;
    field.placeholder = dup ? @"такой город уже есть" : @"Добавить город…";
    [field resignFirstResponder];
    [self reloadCities];
    if (!dup) [tbl scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:cities.count - 1 inSection:0]
                         atScrollPosition:UITableViewScrollPositionBottom animated:YES];
    pc.numberOfPages = cities.count; pc.hidden = cities.count < 2;
}

#pragma mark - table

- (BOOL)typing { return field.text.length > 0; }

- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s {
    return [self typing] ? sugs.count : cities.count;
}

- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *c = [t dequeueReusableCellWithIdentifier:@"c"];
    if (!c) {
        c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"c"];
        c.backgroundColor = [UIColor clearColor];
        c.textLabel.textColor = [UIColor whiteColor];
        c.textLabel.font = [UIFont boldSystemFontOfSize:16];
        c.detailTextLabel.textColor = [UIColor colorWithWhite:1 alpha:.5];
        c.detailTextLabel.font = [UIFont systemFontOfSize:12];
        c.selectionStyle = UITableViewCellSelectionStyleGray;
    }
    c.textLabel.textColor = ink;
    c.detailTextLabel.textColor = [ink colorWithAlphaComponent:.5];
    BOOL typing = [self typing];
    NSDictionary *d = [(typing ? sugs : cities) objectAtIndex:ip.row];
    c.textLabel.text = d[@"name"];
    if (!typing && ip.row == 0) c.detailTextLabel.text = @"моё место";
    else c.detailTextLabel.text = d[@"sub"];
    return c;
}

- (BOOL)tableView:(UITableView *)t canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ![self typing] && ip.row > 0;
}

- (void)tableView:(UITableView *)t commitEditingStyle:(UITableViewCellEditingStyle)st forRowAtIndexPath:(NSIndexPath *)ip {
    if (st != UITableViewCellEditingStyleDelete || ip.row == 0) return;
    [cities removeObjectAtIndex:ip.row];
    [self saveCities];
    if (idx >= (int)cities.count) idx = (int)cities.count - 1;
    [self reloadCities];
    [self showCity];
}

- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)ip {
    if ([self typing]) {
        [self addCityFromDict:[sugs objectAtIndex:ip.row]];
        return;
    }
    idx = (int)ip.row;
    [self closeSettings];
    [self showCity];
}

#pragma mark - swipe

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return settings.hidden; }

- (void)swipe:(UISwipeGestureRecognizer *)g {
    int dir = (g.direction == UISwipeGestureRecognizerDirectionLeft) ? 1 : -1;
    int ni = idx + dir;
    if (ni < 0 || ni >= (int)cities.count) return;
    CGFloat W = self.view.bounds.size.width * 0.5;
    [UIView animateWithDuration:0.16 animations:^{
        content.transform = CGAffineTransformMakeTranslation(-dir * W, 0);
        content.alpha = 0;
    } completion:^(BOOL f) {
        idx = ni;
        [self showCity];
        content.transform = CGAffineTransformMakeTranslation(dir * W, 0);
        [UIView animateWithDuration:0.22 animations:^{
            content.transform = CGAffineTransformIdentity;
            content.alpha = 1;
        }];
    }];
}

- (void)showCity {
    NSDictionary *c = [cities objectAtIndex:idx];
    cityL.text = c[@"name"];
    pc.numberOfPages = cities.count;
    pc.currentPage = idx;
    pc.hidden = cities.count < 2;
    data = cache[[self keyForCity:c]];
    if (data) {
        [self render];
    } else {
        tempL.text = @"--"; iconL.text = @""; descL.text = @"";
        subL.text = @"загрузка…";
        for (int i = 0; i < 3; i++) { ((UILabel *)vals[i]).text = @""; ((UILabel *)caps[i]).text = @""; }
    }
    [self fetch];
}

#pragma mark - data

- (void)refresh {
    if (idx == 0) [self locate];
    [self fetch];
}

- (void)get:(NSString *)u done:(void (^)(id, NSError *))done {
    NSURLRequest *r = [NSURLRequest requestWithURL:[NSURL URLWithString:u]
                                       cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                   timeoutInterval:25];
    [NSURLConnection sendAsynchronousRequest:r queue:[NSOperationQueue mainQueue]
                           completionHandler:^(NSURLResponse *resp, NSData *d, NSError *e) {
        id j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
        done(j, e);
    }];
}

- (void)failWith:(id)j error:(NSError *)e {
    if (data) return;
    if (e) subL.text = [NSString stringWithFormat:@"ошибка %ld", (long)e.code];
    else subL.text = @"ошибка данных";
}

- (void)fetch {
    NSDictionary *c = [cities objectAtIndex:idx];
    NSString *key = [self keyForCity:c];
    loadingKey = key;
    [self pulse:YES];
    NSString *u = [NSString stringWithFormat:@"%@%.4f,%.4f?format=j1&lang=ru",
                   API_BASE, [c[@"lat"] doubleValue], [c[@"lon"] doubleValue]];
    [self get:u done:^(id j, NSError *e) {
        if (![key isEqualToString:loadingKey]) return;
        [self pulse:NO];
        if (![j isKindOfClass:[NSDictionary class]] || ![j[@"current_condition"] count]) {
            [self failWith:j error:e];
            return;
        }
        NSDictionary *n = [self normalizeWttr:j];
        cache[key] = n;
        data = n;
        [self render];
    }];
}

// коды WorldWeatherOnline -> наши типы (0 ясно, 1 облачно, 2 туман, 3 дождь, 4 снег, 5 гроза)
- (int)typeForWWO:(int)w {
    switch (w) {
        case 113: return 0;
        case 116: case 119: case 122: return 1;
        case 143: case 248: case 260: return 2;
        case 200: case 386: case 389: case 392: case 395: return 5;
        case 179: case 227: case 230: case 323: case 326: case 329: case 332: case 335:
        case 338: case 350: case 368: case 371: case 374: case 377: return 4;
        default: return w >= 176 ? 3 : 1;
    }
}

static int DOW(int y, int m, int d) {   // 0 = воскресенье
    static const int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4};
    if (m < 3) y -= 1;
    return (y + y / 4 - y / 100 + y / 400 + t[m - 1] + d) % 7;
}

- (NSDictionary *)normalizeWttr:(NSDictionary *)j {
    NSDictionary *c = [j[@"current_condition"] objectAtIndex:0];
    NSMutableDictionary *n = [NSMutableDictionary dictionary];
    n[@"temp"] = @([c[@"temp_C"] doubleValue]);
    n[@"feels"] = @([c[@"FeelsLikeC"] doubleValue]);
    n[@"hum"] = @([c[@"humidity"] doubleValue]);
    n[@"press"] = @([c[@"pressure"] doubleValue]);
    n[@"wind"] = @([c[@"windspeedKmph"] doubleValue]);
    n[@"type"] = @([self typeForWWO:[c[@"weatherCode"] intValue]]);
    NSArray *ru = c[@"lang_ru"];
    NSArray *en = c[@"weatherDesc"];
    NSString *desc = ([ru isKindOfClass:[NSArray class]] && ru.count) ? [[ru objectAtIndex:0] objectForKey:@"value"]
                   : ([en isKindOfClass:[NSArray class]] && en.count) ? [[en objectAtIndex:0] objectForKey:@"value"] : nil;
    if ([desc isKindOfClass:[NSString class]] && desc.length) n[@"desc"] = desc;

    NSArray *wd = @[@"Вс", @"Пн", @"Вт", @"Ср", @"Чт", @"Пт", @"Сб"];
    NSMutableArray *days = [NSMutableArray array];
    NSArray *w = j[@"weather"];
    for (int i = 0; i < 3 && [w isKindOfClass:[NSArray class]] && i < (int)w.count; i++) {
        NSDictionary *d = [w objectAtIndex:i];
        NSArray *h = d[@"hourly"];
        NSDictionary *mid = h.count > 4 ? [h objectAtIndex:4] : (h.count ? [h lastObject] : nil);
        int y = 0, m = 1, dd = 1;
        sscanf([[d[@"date"] description] UTF8String], "%d-%d-%d", &y, &m, &dd);
        if (m < 1 || m > 12) m = 1;
        [days addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            (i == 0 ? @"Сегодня" : [wd objectAtIndex:DOW(y, m, dd)]), @"wd",
            @([self typeForWWO:[mid[@"weatherCode"] intValue]]), @"type",
            @([d[@"maxtempC"] doubleValue]), @"max",
            @([d[@"mintempC"] doubleValue]), @"min", nil]];
    }
    n[@"days"] = days;
    return n;
}

- (void)render {
    int t = [data[@"type"] intValue];
    [self computeColors:t];
    [self paintBackground];
    [self paintCircle];
    iconL.text = ICON[t];
    NSString *ds = data[@"desc"];
    if (ds.length) ds = [[[ds substringToIndex:1] uppercaseString] stringByAppendingString:[ds substringFromIndex:1]];
    descL.text = ds.length ? ds : NAME[t];
    tipL.text = tips ? [self tipText] : @"";
    tempL.text = [NSString stringWithFormat:@"%ld\u00B0", [self T:[data[@"temp"] doubleValue]]];
    subL.text = [NSString stringWithFormat:@"ощущается как %ld\u00B0", [self T:[data[@"feels"] doubleValue]]];
    [self setParticles:t];
    [self fillCard];
}

- (void)fillCard {
    if (!data) return;
    NSString *v[3] = {@"", @"", @""}, *k[3] = {@"", @"", @""};
    if (!showForecast) {
        v[0] = [NSString stringWithFormat:@"%ld км/ч", lround([data[@"wind"] doubleValue])];
        v[1] = [NSString stringWithFormat:@"%ld%%", lround([data[@"hum"] doubleValue])];
        v[2] = [NSString stringWithFormat:@"%ld мм", lround([data[@"press"] doubleValue] * 0.75006)];
        k[0] = @"ветер"; k[1] = @"влажность"; k[2] = @"давление";
    } else {
        NSArray *days = data[@"days"];
        for (int i = 0; i < 3 && i < (int)days.count; i++) {
            NSDictionary *d = [days objectAtIndex:i];
            v[i] = [NSString stringWithFormat:@"%@ %ld\u00B0", ICON[[d[@"type"] intValue]], [self T:[d[@"max"] doubleValue]]];
            k[i] = [NSString stringWithFormat:@"%@ \u00B7 %ld\u00B0", d[@"wd"], [self T:[d[@"min"] doubleValue]]];
        }
    }
    for (int i = 0; i < 3; i++) {
        ((UILabel *)vals[i]).text = v[i];
        ((UILabel *)caps[i]).text = k[i];
    }
}

- (void)toggle {
    showForecast = !showForecast;
    [UIView transitionWithView:card duration:0.3 options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{ [self fillCard]; } completion:nil];
}

#pragma mark - colors and mode

- (void)computeColors:(int)t {
    CGFloat a[3];
    if (theme == 0) {
        a[0] = P[t][6]; a[1] = P[t][7]; a[2] = P[t][8];
    } else if (theme <= 7) {
        a[0] = PAL[theme - 1][0]; a[1] = PAL[theme - 1][1]; a[2] = PAL[theme - 1][2];
    } else {
        UIColor *hc = [UIColor colorWithHue:hue saturation:0.62 brightness:0.95 alpha:1];
        CGFloat al;
        [hc getRed:&a[0] green:&a[1] blue:&a[2] alpha:&al];
    }
    CGFloat tp[3], bt[3];
    for (int k = 0; k < 3; k++) {
        if (light)            { tp[k] = a[k] * 0.22 + 0.78; bt[k] = a[k] * 0.45 + 0.55; }
        else if (theme == 0)  { tp[k] = P[t][k];            bt[k] = P[t][3 + k]; }
        else                  { tp[k] = a[k] * 0.32 + 0.03; bt[k] = a[k] * 0.12 + 0.02; }
    }
    accent = [UIColor colorWithRed:a[0] green:a[1] blue:a[2] alpha:1];
    bgTop = [UIColor colorWithRed:tp[0] green:tp[1] blue:tp[2] alpha:1];
    bgBot = [UIColor colorWithRed:bt[0] green:bt[1] blue:bt[2] alpha:1];
}

- (void)paintBackground {
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.4];
    bg.colors = @[(id)bgTop.CGColor, (id)bgBot.CGColor];
    [CATransaction commit];
}

- (void)refreshColors {
    [self computeColors:data ? [data[@"type"] intValue] : 1];
    [self paintBackground];
    [self paintCircle];
}

// перекрашиваем подписи и «стеклянные» элементы под тёмный/светлый режим
- (void)tintTree:(UIView *)root {
    for (UIView *v in root.subviews) {
        if (v == circle) continue;
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            l.textColor = [ink colorWithAlphaComponent:CGColorGetAlpha(l.textColor.CGColor)];
        } else if (v.tag >= 700 && v.tag < 800) {
            CGFloat a = (v.tag - 700) / 100.0;
            if (light) {
                v.backgroundColor = [UIColor colorWithWhite:1 alpha:MIN(0.9, a * 4)];
                v.layer.borderColor = [UIColor colorWithWhite:1 alpha:.7].CGColor;
            } else {
                v.backgroundColor = [UIColor colorWithWhite:1 alpha:a];
                v.layer.borderColor = [UIColor colorWithWhite:1 alpha:.12].CGColor;
            }
        } else if (v.tag == 900) {
            v.backgroundColor = ink;
        }
        [self tintTree:v];
    }
}

- (void)applyMode {
    ink = light ? [UIColor colorWithRed:.12 green:.14 blue:.20 alpha:1] : [UIColor whiteColor];
    settings.backgroundColor = light ? [UIColor colorWithRed:.88 green:.90 blue:.94 alpha:.97]
                                     : [UIColor colorWithWhite:0 alpha:.9];
    [self tintTree:self.view];
    field.textColor = ink;
    tbl.separatorColor = [ink colorWithAlphaComponent:.15];
    pc.pageIndicatorTintColor = [ink colorWithAlphaComponent:.3];
    pc.currentPageIndicatorTintColor = ink;
    [self updateSwatches];
    [self refreshColors];
    [self reloadCities];
    [self setParticles:lastType];
}

#pragma mark - style and tips

- (void)applyStyle {
    CGFloat w = self.view.bounds.size.width, h = self.view.bounds.size.height;
    CGRect f; CGFloat r;
    if (style == 1)      { f = CGRectMake(0, h * 0.18, w, 200); r = 0; }
    else if (style == 2) { f = CGRectMake(20, h * 0.22, w - 40, 150); r = 28; }
    else                 { f = CGRectMake((w - 180) / 2, h * 0.21, 180, 180); r = 90; }
    circle.frame = f;
    circle.layer.cornerRadius = r;
    gloss.frame = circle.bounds;
    gloss.cornerRadius = r;
    circle.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:circle.bounds cornerRadius:r].CGPath;
    CGFloat cw = f.size.width;
    if (style == 1) {
        iconL.frame = CGRectMake(0, 4, cw, 56);
        iconL.font = [UIFont systemFontOfSize:44];
        tempL.frame = CGRectMake(0, 58, cw, 140);
        tempL.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:124] ?: [UIFont systemFontOfSize:110];
    } else if (style == 2) {
        iconL.frame = CGRectMake(10, 30, 110, 90);
        iconL.font = [UIFont systemFontOfSize:64];
        tempL.frame = CGRectMake(120, 26, cw - 130, 98);
        tempL.font = [UIFont boldSystemFontOfSize:72];
    } else {
        iconL.frame = CGRectMake(0, 22, 180, 50);
        iconL.font = [UIFont systemFontOfSize:38];
        tempL.frame = CGRectMake(0, 68, 180, 76);
        tempL.font = [UIFont boldSystemFontOfSize:66];
    }
    descL.frame = CGRectMake(0, CGRectGetMaxY(f) + (style == 1 ? 2 : 14), w, 24);
    tipL.frame = CGRectMake(20, CGRectGetMaxY(descL.frame) + 2, w - 40, 18);
    [self paintCircle];
}

- (void)paintCircle {
    circle.layer.shadowColor = accent.CGColor;
    UIColor *tc = (style == 1 && light) ? ink : [UIColor whiteColor];
    iconL.textColor = tc;
    tempL.textColor = tc;
    circle.layer.shadowOpacity = (style == 1) ? 0 : 0.7;
    gloss.hidden = (style == 1);
    UIColor *bgc = (style == 1) ? [UIColor clearColor] : accent;
    [UIView animateWithDuration:0.6 animations:^{ circle.backgroundColor = bgc; }];
}

- (void)styleChanged {
    style = (int)styleSeg.selectedSegmentIndex;
    [ud setInteger:style forKey:@"style"]; [ud synchronize];
    [UIView animateWithDuration:0.12 animations:^{ circle.alpha = 0; }
                     completion:^(BOOL f) {
        [self applyStyle];
        [UIView animateWithDuration:0.2 animations:^{ circle.alpha = 1; }];
    }];
}

- (void)tipsChanged {
    tips = tipSw.on;
    [ud setBool:tips forKey:@"tips"]; [ud synchronize];
    tipL.text = (tips && data) ? [self tipText] : @"";
}

- (NSString *)tipText {
    int t = [data[@"type"] intValue];
    double tc = [data[@"temp"] doubleValue], wind = [data[@"wind"] doubleValue];
    if (t == 5) return @"Гроза, лучше остаться дома";
    if (t == 3) return @"Возьми зонт";
    if (t == 4) return @"Скользко, одевайся теплее";
    if (wind >= 40) return @"Сильный ветер, держись крепче";
    if (tc <= -10) return @"Лютый мороз: шапка и шарф";
    if (tc <= 0) return @"Мороз, надень тёплую куртку";
    if (tc <= 10) return @"Прохладно, нужна куртка";
    if (tc <= 18) return @"Хватит свитера или лёгкой куртки";
    if (tc <= 26) return @"Отличная погода для прогулки";
    return @"Жарко, пей больше воды";
}

#pragma mark - effects

- (void)pulse:(BOOL)on {
    [circle.layer removeAnimationForKey:@"pulse"];
    if (!on) return;
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    a.fromValue = @1; a.toValue = @1.07; a.duration = 0.7;
    a.autoreverses = YES; a.repeatCount = HUGE_VALF;
    [circle.layer addAnimation:a forKey:@"pulse"];
}

- (UIImage *)dot:(CGSize)s {
    UIGraphicsBeginImageContextWithOptions(s, NO, 0);
    [[UIColor whiteColor] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, s.width, s.height)
                                cornerRadius:MIN(s.width, s.height) / 2] fill];
    UIImage *i = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return i;
}

- (void)setParticles:(int)t {
    lastType = t;
    CGSize sz = self.view.bounds.size;
    CAEmitterCell *c = [CAEmitterCell emitterCell];
    UIImage *cat = cats ? [UIImage imageNamed:@"cat.png"] : nil;
    if (cat) {                         // котики падают как снег
        emitter.emitterShape = kCAEmitterLayerLine;
        emitter.emitterPosition = CGPointMake(sz.width / 2, -20);
        emitter.emitterSize = CGSizeMake(sz.width, 1);
        c.contents = (id)cat.CGImage;
        c.birthRate = CAT_RATE; c.lifetime = 16;
        c.velocity = 38; c.velocityRange = 18;
        c.emissionLongitude = M_PI; c.emissionRange = 0.5;
        c.spin = 0.4; c.spinRange = 1.2;
        c.scale = CAT_SCALE; c.scaleRange = 0.2;
        c.color = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    } else if (t == 3 || t == 5) {     // дождь
        emitter.emitterShape = kCAEmitterLayerLine;
        emitter.emitterPosition = CGPointMake(sz.width / 2, -10);
        emitter.emitterSize = CGSizeMake(sz.width + 40, 1);
        c.contents = (id)[self dot:CGSizeMake(2, 14)].CGImage;
        c.birthRate = 45; c.lifetime = 1.6;
        c.velocity = 330; c.velocityRange = 60;
        c.emissionLongitude = M_PI - 0.12;
        c.color = (light ? [ink colorWithAlphaComponent:.35] : [UIColor colorWithWhite:1 alpha:.35]).CGColor;
    } else if (t == 4) {               // снег
        emitter.emitterShape = kCAEmitterLayerLine;
        emitter.emitterPosition = CGPointMake(sz.width / 2, -10);
        emitter.emitterSize = CGSizeMake(sz.width, 1);
        c.contents = (id)[self dot:CGSizeMake(7, 7)].CGImage;
        c.birthRate = 14; c.lifetime = 9;
        c.velocity = 35; c.velocityRange = 20;
        c.emissionLongitude = M_PI; c.emissionRange = 0.6;
        c.scale = 0.6; c.scaleRange = 0.5;
        c.color = [UIColor colorWithWhite:1 alpha:.7].CGColor;
    } else {                           // пылинки света
        emitter.emitterShape = kCAEmitterLayerRectangle;
        emitter.emitterPosition = CGPointMake(sz.width / 2, sz.height / 2);
        emitter.emitterSize = sz;
        c.contents = (id)[self dot:CGSizeMake(6, 6)].CGImage;
        c.birthRate = 3; c.lifetime = 8;
        c.velocity = 8; c.velocityRange = 10;
        c.emissionRange = 2 * M_PI;
        c.scale = 0.5; c.scaleRange = 0.4; c.alphaSpeed = -0.04;
        c.color = (light ? [ink colorWithAlphaComponent:.25] : [UIColor colorWithWhite:1 alpha:.3]).CGColor;
    }
    emitter.emitterCells = @[c];
}

#pragma mark - location

- (void)locate {
    if (![CLLocationManager locationServicesEnabled]) return;
    [lm startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray *)ls {
    [m stopUpdatingLocation];
    CLLocation *l = [ls lastObject];
    NSMutableDictionary *g = [cities objectAtIndex:0];
    g[@"lat"] = @(l.coordinate.latitude);
    g[@"lon"] = @(l.coordinate.longitude);
    if (idx == 0) [self fetch];
    [[[CLGeocoder alloc] init] reverseGeocodeLocation:l completionHandler:^(NSArray *pl, NSError *e) {
        CLPlacemark *p = pl.count ? [pl objectAtIndex:0] : nil;
        if (p.locality) {
            g[@"name"] = p.locality;
            if (idx == 0) cityL.text = p.locality;
            [self reloadCities];
        }
    }];
}

- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)e {
    [m stopUpdatingLocation];
}

@end
