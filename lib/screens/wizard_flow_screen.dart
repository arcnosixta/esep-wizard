import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'wizard_result_screen.dart';

/// Wizard: пошаговый поток оценки имущества.
class WizardFlowScreen extends StatefulWidget {
  const WizardFlowScreen({super.key});

  @override
  State<WizardFlowScreen> createState() => _WizardFlowScreenState();
}

class _WizardFlowScreenState extends State<WizardFlowScreen> {
  final _pageController = PageController();
  int _currentStep = 0;

  /// Данные, собранные по шагам.
  final _data = <String, dynamic>{
    'propertyType': 0,
    'address': '',
    'area': '',
    'rooms': '',
    'floor': '',
    'totalFloors': '',
    'condition': 'Косметический ремонт',
    'yearBuilt': '',
    'photos': <String>[],
    'purpose': 'Для продажи',
  };

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentStep == 1 && (_data['address'] as String).trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите адрес объекта')),
      );
      return;
    }
    if (_currentStep == 2 && (_data['area'] as String).trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите площадь')),
      );
      return;
    }

    if (_currentStep < 6) {
      setState(() => _currentStep++);
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    } else {
      _showResult();
    }
  }

  void _prev() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _showResult() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => WizardResultScreen(data: _data)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final steps = const [
      'Что оцениваем?',
      'Где находится?',
      'Характеристики',
      'Фотографии',
      'Документы',
      'Цель оценки',
      'Результат',
    ];

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: Text('Шаг ${_currentStep + 1} из 7'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Прогресс-индикатор
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(
              children: List.generate(7, (i) {
                final isActive = i <= _currentStep;
                final isDone = i < _currentStep;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDone
                              ? c.accent
                              : isActive
                                  ? c.accent.withValues(alpha: 0.2)
                                  : c.border,
                        ),
                        child: Center(
                          child: isDone
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : isActive
                                  ? Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: c.accent,
                                      ),
                                    )
                                  : Text(
                                      '${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.textHint,
                                      ),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          steps[i],
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                            color: isActive ? c.textPrimary : c.textHint,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const BouncingScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _Step1PropertyType(data: _data),
                _Step2Address(data: _data),
                _Step3Characteristics(data: _data),
                _Step4Photos(data: _data),
                _Step5Documents(data: _data),
                _Step6Purpose(data: _data),
                _Step7Result(data: _data),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(
                children: [
                  if (_currentStep > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _prev,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Назад',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (_currentStep > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: _currentStep > 0 ? 2 : 1,
                    child: FilledButton(
                      onPressed: _next,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _currentStep == 6 ? 'Посмотреть результат' : 'Далее',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step1PropertyType extends StatefulWidget {
  final Map<String, dynamic> data;
  const _Step1PropertyType({required this.data});

  @override
  State<_Step1PropertyType> createState() => _Step1PropertyTypeState();
}

class _Step1PropertyTypeState extends State<_Step1PropertyType> {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Что вы хотели бы оценить?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Выберите один вариант',
            style: TextStyle(
              fontSize: 15,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          GridView.count(
            crossAxisCount: 2,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _typeCard(context, 'Квартира', Icons.apartment_rounded, 0),
              _typeCard(context, 'Дом', Icons.house_rounded, 1),
              _typeCard(context, 'Земля', Icons.terrain_rounded, 2),
              _typeCard(context, 'Авто', Icons.directions_car_rounded, 3),
              _typeCard(context, 'Коммерция', Icons.business_rounded, 4),
              _typeCard(context, 'Другое', Icons.inventory_rounded, 5),
            ],
          ),
        ],
      ),
    );
  }

  Widget _typeCard(BuildContext context, String label, IconData icon, int index) {
    final c = AppColors.of(context);
    final selected = widget.data['propertyType'] == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.data['propertyType'] = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.1) : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c.accent : c.border, width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: selected ? c.accent : c.textSecondary),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? c.accent : c.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step2Address extends StatefulWidget {
  final Map<String, dynamic> data;
  const _Step2Address({required this.data});

  @override
  State<_Step2Address> createState() => _Step2AddressState();
}

class _Step2AddressState extends State<_Step2Address> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.data['address'] as String? ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Где находится объект?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Укажите адрес или координаты',
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Например: г. Алматы, ул. Жамбыла, д. 114',
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: c.accent, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onChanged: (v) => widget.data['address'] = v,
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _controller.text = 'г. Алматы, ул. Примерная, д. 1';
                widget.data['address'] = _controller.text;
              });
            },
            icon: const Icon(Icons.my_location_rounded, size: 20),
            label: const Text('Использовать местоположение'),
          ),
        ],
      ),
    );
  }
}

class _Step3Characteristics extends StatefulWidget {
  final Map<String, dynamic> data;
  const _Step3Characteristics({required this.data});

  @override
  State<_Step3Characteristics> createState() => _Step3CharacteristicsState();
}

class _Step3CharacteristicsState extends State<_Step3Characteristics> {
  late final TextEditingController _areaCtrl;
  late final TextEditingController _roomsCtrl;
  late final TextEditingController _floorCtrl;
  late final TextEditingController _totalFloorsCtrl;
  late final TextEditingController _yearBuiltCtrl;

  @override
  void initState() {
    super.initState();
    _areaCtrl = TextEditingController(text: widget.data['area'] as String? ?? '');
    _roomsCtrl = TextEditingController(text: widget.data['rooms'] as String? ?? '');
    _floorCtrl = TextEditingController(text: widget.data['floor'] as String? ?? '');
    _totalFloorsCtrl =
        TextEditingController(text: widget.data['totalFloors'] as String? ?? '');
    _yearBuiltCtrl = TextEditingController(text: widget.data['yearBuilt'] as String? ?? '');
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _roomsCtrl.dispose();
    _floorCtrl.dispose();
    _totalFloorsCtrl.dispose();
    _yearBuiltCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final propertyType = (widget.data['propertyType'] as int?) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Характеристики объекта',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Укажите основные параметры',
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          _buildField(context, 'Площадь (м²)', _areaCtrl,
              keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          if (propertyType == 0 || propertyType == 1)
            _buildField(context, 'Комнаты', _roomsCtrl,
                keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          if (propertyType == 0)
            _buildField(context, 'Этаж', _floorCtrl,
                keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          if (propertyType == 0)
            _buildField(context, 'Всего этажей', _totalFloorsCtrl,
                keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          _buildField(context, 'Год постройки', _yearBuiltCtrl,
              keyboardType: TextInputType.number),
          const SizedBox(height: 24),
          const SizedBox(height: 8),
          Text(
            'Состояние объекта',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _conditionChip(context, 'Без ремонта', 'Без ремонта'),
              _conditionChip(context, 'Косметический ремонт', 'Косметический ремонт'),
              _conditionChip(context, 'Капитальный ремонт', 'Капитальный ремонт'),
              _conditionChip(context, 'Дизайнерский ремонт', 'Дизайнерский ремонт'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(BuildContext context, String label, TextEditingController controller,
      {TextInputType keyboardType = TextInputType.text}) {
    final c = AppColors.of(context);
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: c.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      onChanged: (v) {
        if (label == 'Площадь (м²)') widget.data['area'] = v;
        if (label == 'Комнаты') widget.data['rooms'] = v;
        if (label == 'Этаж') widget.data['floor'] = v;
        if (label == 'Всего этажей') widget.data['totalFloors'] = v;
        if (label == 'Год постройки') widget.data['yearBuilt'] = v;
      },
    );
  }

  Widget _conditionChip(BuildContext context, String label, String value) {
    final c = AppColors.of(context);
    final selected = widget.data['condition'] == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.data['condition'] = value;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.1) : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c.accent : c.border, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? c.accent : c.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _Step4Photos extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Step4Photos({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Фотографии объекта',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text('(опционально)',
                  style: TextStyle(fontSize: 13, color: c.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Загрузите фото объекта для более точной оценки',
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 1.5),
              image: data['photos'].isNotEmpty
                  ? DecorationImage(
                      image: NetworkImage(data['photos'][0]), fit: BoxFit.cover)
                  : null,
            ),
            child: data['photos'].isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_rounded, size: 40,
                            color: c.textHint),
                        const SizedBox(height: 8),
                        Text('Нажмите, чтобы загрузить фото',
                            style: TextStyle(fontSize: 13, color: c.textHint)),
                      ],
                    ),
                  )
                : null,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Загрузка фото — в разработке')));
            },
            icon: const Icon(Icons.camera_alt_rounded, size: 20),
            label: const Text('Добавить фото'),
          ),
        ],
      ),
    );
  }
}

class _Step5Documents extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Step5Documents({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Документы объекта',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              const Spacer(),
              Text('(опционально)',
                  style: TextStyle(fontSize: 13, color: c.textHint)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Приложите документы: правоустанавливающие, планы, фото',
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 1.5),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_file_rounded, size: 40, color: c.textHint),
                  const SizedBox(height: 8),
                  Text('Нажмите, чтобы загрузить документы',
                      style: TextStyle(fontSize: 13, color: c.textHint)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Загрузка документов — в разработке')));
            },
            icon: const Icon(Icons.upload_file_rounded, size: 20),
            label: const Text('Загрузить документы'),
          ),
        ],
      ),
    );
  }
}

class _Step6Purpose extends StatefulWidget {
  final Map<String, dynamic> data;
  const _Step6Purpose({required this.data});

  @override
  State<_Step6Purpose> createState() => _Step6PurposeState();
}

class _Step6PurposeState extends State<_Step6Purpose> {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final purposes = [
      ('Для продажи', 'Продажа имущества'),
      ('Для покупки', 'Покупка имущества'),
      ('Для кредита (залог)', 'Залог для кредита'),
      ('Просто узнать стоимость', 'Информация'),
    ];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            'Для чего нужна оценка?',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Это поможет подготовить правильный отчёт',
            style: TextStyle(fontSize: 15, color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          ...purposes.map((p) => _purposeCard(context, p.$1, p.$2)),
        ],
      ),
    );
  }

  Widget _purposeCard(BuildContext context, String title, String subtitle) {
    final c = AppColors.of(context);
    final selected = widget.data['purpose'] == title;
    return GestureDetector(
      onTap: () {
        setState(() {
          widget.data['purpose'] = title;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? c.accent.withValues(alpha: 0.1) : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? c.accent : c.border, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? c.accent : c.textHint,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? c.accent : c.textPrimary,
                    ),
                  ),
                  Text(subtitle, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step7Result extends StatelessWidget {
  final Map<String, dynamic> data;
  const _Step7Result({required this.data});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final propertyType = (data['propertyType'] as int?) ?? 0;
    final types = ['Квартира', 'Дом', 'Земля', 'Авто', 'Коммерция', 'Другое'];
    final typeName = types[propertyType.clamp(0, types.length - 1)];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Icon(Icons.check_circle_rounded, size: 72, color: c.accent),
          const SizedBox(height: 20),
          Text(
            'Данные собраны!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: c.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Теперь мы можем подготовить для вас официальный отчёт',
            style: TextStyle(
              fontSize: 16,
              color: c.textSecondary,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryRow(context, 'Объект', typeName),
                const SizedBox(height: 12),
                if ((data['address'] as String).isNotEmpty)
                  _summaryRow(context, 'Адрес', data['address'] as String),
                if ((data['area'] as String).isNotEmpty)
                  _summaryRow(context, 'Площадь', '${data['area']} м²'),
                if (data['purpose'] != null)
                  _summaryRow(context, 'Цель', data['purpose'] as String),
              ],
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => WizardResultScreen(data: data),
                ),
              );
            },
            icon: const Icon(Icons.description_rounded),
            label: const Text('Перейти к отчёту'),
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Отмена', style: TextStyle(fontSize: 15, color: c.textSecondary)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 14, color: c.textSecondary)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
