use crate::db;
use rust_xlsxwriter::*;

pub async fn export_json(session_id: String) -> anyhow::Result<Vec<u8>> {
    let entries = db::logs::get_all_logs_in_session(&session_id).await?;
    let json = serde_json::to_string_pretty(&entries)?;
    Ok(json.into_bytes())
}

pub async fn export_excel(session_id: String) -> anyhow::Result<Vec<u8>> {
    let entries = db::logs::get_all_logs_in_session(&session_id).await?;

    let mut workbook = Workbook::new();

    // Header format
    let header_fmt = Format::new()
        .set_bold()
        .set_background_color(Color::RGB(0xE4E4E7))
        .set_border(FormatBorder::Thin)
        .set_align(FormatAlign::Center);

    // Cell format
    let cell_fmt = Format::new()
        .set_border(FormatBorder::Thin)
        .set_align(FormatAlign::Left);

    // Alternating row color
    let alt_fmt = Format::new()
        .set_border(FormatBorder::Thin)
        .set_background_color(Color::RGB(0xF4F4F5))
        .set_align(FormatAlign::Left);

    let worksheet = workbook.add_worksheet();
    worksheet.set_name("Logs")?;

    // Column widths
    worksheet.set_column_width(0, 10)?; // time
    worksheet.set_column_width(1, 12)?; // controller
    worksheet.set_column_width(2, 14)?; // callsign
    worksheet.set_column_width(3, 10)?; // rst_sent
    worksheet.set_column_width(4, 10)?; // rst_rcvd
    worksheet.set_column_width(5, 14)?; // qth
    worksheet.set_column_width(6, 16)?; // device
    worksheet.set_column_width(7, 14)?; // antenna
    worksheet.set_column_width(8, 8)?; // power
    worksheet.set_column_width(9, 8)?; // height

    // Headers
    let headers = ["时间", "主控", "呼号", "RST发", "RST收", "QTH", "设备", "天线", "功率", "高度"];
    for (col, header) in headers.iter().enumerate() {
        worksheet.write_with_format(0, col as u16, *header, &header_fmt)?;
    }

    // Data rows
    for (row, entry) in entries.iter().enumerate() {
        let r = (row + 1) as u32;
        let fmt = if row % 2 == 1 { &alt_fmt } else { &cell_fmt };

        worksheet.write_with_format(r, 0, &entry.time[11..16], fmt)?;
        worksheet.write_with_format(r, 1, &entry.controller, fmt)?;
        worksheet.write_with_format(r, 2, &entry.callsign, fmt)?;
        worksheet.write_with_format(r, 3, entry.rst_sent.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 4, entry.rst_rcvd.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 5, entry.qth.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 6, entry.device.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 7, entry.antenna.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 8, entry.power.as_deref().unwrap_or(""), fmt)?;
        worksheet.write_with_format(r, 9, entry.height.as_deref().unwrap_or(""), fmt)?;
    }

    let bytes = workbook.save_to_buffer()?;
    Ok(bytes)
}
