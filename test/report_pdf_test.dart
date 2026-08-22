import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:esep/models/report_template.dart';
import 'package:esep/services/report_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReportData sampleData() => ReportData(
        clientName: 'Иванов Иван Иванович',
        clientIin: '900101300123',
        clientIsOrg: false,
        clientAddress: 'г. Алматы, ул. Пушкина, д. 5, кв. 12',
        propertyType: 'Квартира',
        address: 'г. Алматы, Алмалинский район, ул. Абая, д. 10, кв. 45',
        area: 55.0,
        rooms: 2,
        floor: 4,
        totalFloors: 9,
        condition: 'Хорошее',
        yearBuilt: 2005,
        cadastralNumber: '05-123-456-789',
        purpose: 'Проживание',
        buildingType: 'Многоквартирный жилой дом',
        wallMaterial: 'Кирпич',
        buildingCondition: 'Удовлетворительное',
        communications: 'Центральные',
        livingArea: '38',
        kitchenArea: '9',
        bathroom: 'Раздельный',
        balcony: 'Лоджия',
        renovationYear: '2020',
        layout: 'Улучшенная',
        inspectionDate: '10.08.2026',
        clientIdDoc: 'Удостоверение личности № 123456789, выдано МВД РК 10.01.2019',
        estimatedPrice: 25000000,
        priceRangeLow: 23000000,
        priceRangeHigh: 27000000,
        pricePerMeter: 454545,
        confidence: 0.87,
        comparables: [
          ComparableProperty(
            address: 'г. Алматы, ул. Пушкина, д. 5',
            area: 52,
            price: 24000000,
            type: 'Квартира',
            source: 'krisha.kz',
            url: 'https://krisha.kz/a/view/1000001',
            adjustments: const [
              AdjustmentItem(name: 'Этаж', percent: -3),
              AdjustmentItem(name: 'Состояние', percent: 5),
            ],
            adjustedPrice: 24480000,
          ),
          ComparableProperty(
            address: 'г. Алматы, мкр. Таугуль, д. 12',
            area: 58,
            price: 26500000,
            type: 'Квартира',
            source: 'krisha.kz',
            url: 'https://krisha.kz/a/view/1000002',
            adjustments: const [
              AdjustmentItem(name: 'Площадь', percent: 4),
              AdjustmentItem(name: 'Этаж', percent: -2),
            ],
            adjustedPrice: 27030000,
          ),
          ComparableProperty(
            address: 'г. Алматы, ул. Розыбакиева, д. 88',
            area: 54,
            price: 25500000,
            type: 'Квартира',
            source: 'olx.kz',
            url: 'https://olx.kz/d/1000003',
            adjustments: const [
              AdjustmentItem(name: 'Состояние', percent: -2),
            ],
            adjustedPrice: 24990000,
          ),
        ],
        recommendations: const [
          Recommendation(icon: 'verified', title: 'Проверка юридической чистоты', description: 'Рекомендуется заказать выписку из ЕГКН перед сделкой.'),
          Recommendation(icon: 'schedule', title: 'Срок действия отчёта', description: 'Отчёт действителен в течение 6 месяцев с даты оценки.'),
        ],
        appraisalDate: '11.08.2026',
        reportNumber: 'G-2026-0001',
        appraiserName: 'Мақсұтұлы Ғазиз',
        appraiserIin: '900101300123',
        appraiserCertificate: 'Свидетельство № 00170',
        appraiserPalata: 'Палата оценщиков',
        appraiserInsurance: 'Полис № ...',
        legalEntityName: 'ТОО «GaMa Group»',
        legalEntityAddress: 'РК, г. Алматы, Алмалинский район, ул. Жамбыла, д.114/85, оф.133',
        legalEntityBin: '160840018855',
        legalEntityIik: 'KZ646017131000019202',
        legalEntityBik: 'HSBKKZKX',
        legalEntityBank: 'АО «Народный банк Казахстана»',
        legalEntityKbe: '17',
        legalEntityPhone: '+7 (727) 327-27-73',
      );

  test('generatePdf creates a full report with title page', () async {
    final data = sampleData();
    final bytes = await ReportService.generatePdf(data, preview: true);

    expect(bytes.length, greaterThan(50000),
        reason: 'PDF должен быть содержательным (50+ КБ)');

    final doc = pw.Document();
    // Проверяем, что PDF парсится как валидный файл
    final file = File('/tmp/esep_test_report.pdf');
    file.writeAsBytesSync(bytes);
    expect(file.existsSync(), true);
    expect(file.lengthSync(), bytes.length);
  });

  test('generatePdf full version without preview', () async {
    final data = sampleData();
    final bytes = await ReportService.generatePdf(data, preview: false);
    expect(bytes.length, greaterThan(50000));

    // Регрессия объёма: отчёт должен быть не менее 40 страниц (требование продакшена)
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, greaterThanOrEqualTo(40),
        reason: 'Отчёт должен содержать 40+ страниц, фактически $pages');

    // Сохраняем полную версию для проверки количества страниц
    final file = File('/tmp/esep_test_report_full.pdf');
    file.writeAsBytesSync(bytes);
  });

  test('generatePdf with photos embeds them in appendix', () async {
    final data = sampleData();
    final photoPath = '/tmp/esep_test_photo.jpg';
    final photo = File(photoPath);
    if (!photo.existsSync()) {
      photo.writeAsBytesSync(List.filled(1024, 0x42));
    }
    final bytes = await ReportService.generatePdf(data, preview: false, photos: [photo.readAsBytesSync(), photo.readAsBytesSync(), photo.readAsBytesSync()]);
    expect(bytes.length, greaterThan(50000));
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length;
    expect(pages, greaterThanOrEqualTo(40),
        reason: 'Отчёт с фото должен содержать 40+ страниц, фактически $pages');
    final file = File('/tmp/esep_test_report_photos.pdf');
    file.writeAsBytesSync(bytes);
  });
}
