// import { utcToZonedTime, format } from 'date-fns-tz';
import { toZonedTime, format } from 'date-fns-tz';
export function formatDatePlus3Days(dateString: string): string | null {
    if (!dateString) return null;

    const date = new Date(dateString);
    if (isNaN(date.getTime())) return null;

    date.setDate(date.getDate() + 3);
    return new Intl.DateTimeFormat('en-US').format(date);
}

export function formatBilledDateUTC(date: string | Date): string {
    const zonedDate = toZonedTime(new Date(date), 'UTC');
    return format(zonedDate, 'dd/MM/yyyy', { timeZone: 'UTC' });
}

// export class BitToBooleanTransformer {
//     to(value: boolean | null): Buffer | null {
//         if (value === null) {
//             return null;
//         }
//         const res = Buffer.alloc(1);
//         res[0] = value ? 1 : 0;
//         return res;
//     }
//     from(value: Buffer): boolean | null {
//         if (value === null) {
//             return null;
//         }
//         return value[0] === 1;
//     }
// }


export function transformPatientCounts(rawData: any[], useRevenue = false): Record<string, any>[] {
    const resultMap: Record<string, any> = {};
    const allLocations = new Set<string>();

    console.log('rawData', rawData);
    for (const row of rawData) {
        const date = row.visit_date || "Unknown Date";
        const locationName = row.location_name || "Unknown Location";

        const value = useRevenue
            ? parseFloat(row.total_revenue || 0)
            : parseInt(row.patient_count || 0, 10);

        if (!resultMap[date]) {
            resultMap[date] = { date };
        }



        resultMap[date][locationName] = value;
        allLocations.add(locationName);
    }

    console.log('resultMap', resultMap);
    console.log('allLocations', allLocations);
    const locationList = Array.from(allLocations);

    console.log('locationList', locationList);
    for (const date in resultMap) {
        for (const loc of locationList) {
            if (!(loc in resultMap[date])) {
                resultMap[date][loc] = "-";
            }
        }
    }

    return Object.values(resultMap);
}


export function transformAttorneyData(
    apiData: any[],
    type: 'count' | 'sum'
): Record<string, any>[] {
    if (!apiData || apiData.length === 0) return [];

    const allDates = new Set<string>();
    const groupedByAttorney = apiData.reduce((acc: any, item: any) => {
        const attorneyName = item.attorney_name || 'Unknown Attorney';
        const dateKey =
            type === 'count'
                ? item.visit_date
                : item.billed_date;


        if (!dateKey) return acc;

        allDates.add(dateKey);

        if (!acc[attorneyName]) {
            acc[attorneyName] = { attorney: attorneyName };
        }

        const value =
            type === 'count'
                ? parseInt(item.total_patient_visits || item.patient_count || '0', 10)
                : `$${parseFloat(item.total_billed_charges).toFixed(2)}`;

        console.log(value, 'value of function');

        acc[attorneyName][dateKey] = value;

        return acc;
    }, {});

    const dateList = Array.from(allDates);

    // Fill in missing dates with 0 or "0.00"
    for (const attorneyName in groupedByAttorney) {
        for (const date of dateList) {
            if (!(date in groupedByAttorney[attorneyName])) {
                groupedByAttorney[attorneyName][date] = type === 'sum' ? "$0.00" : "-";
            }
        }
    }

    return Object.values(groupedByAttorney);
}




export const transformAttorneySettlementsData = (apiData: any[]): Record<string, any>[] => {
    if (!apiData || apiData.length === 0) return [];

    const dateSet = new Set<string>();
    apiData.forEach(item => dateSet.add(item.settlement_date_formatted));

    const uniqueDates = Array.from(dateSet).sort(
        (a, b) => new Date(a).getTime() - new Date(b).getTime()
    );

    const groupedByAttorney = new Map<string, Record<string, any>>();

    for (const item of apiData) {
        const attorneyName = item.attorney_name || `Attorney ${item.attorney_id}`;
        const date = item.settlement_date_formatted;
        const amount = `$${parseFloat(item.total_settlement_amount)}` || "$0.00";

        if (!groupedByAttorney.has(attorneyName)) {
            const initialRecord: Record<string, any> = { attorney: attorneyName };
            for (const d of uniqueDates) {
                initialRecord[d] = "$0.00";
            }
            groupedByAttorney.set(attorneyName, initialRecord);
        }

        groupedByAttorney.get(attorneyName)![date] = amount;
    }

    return Array.from(groupedByAttorney.values());
};




export const transformSettlementSummaryData = (apiData: any[]): any[] => {
    if (!apiData || apiData.length === 0) return [];

    return apiData.map((item) => ({
        period: item.settlement_date_formatted,
        patient_count: parseInt(item.patient_count || "0", 10),
        total_billed_charges: `$${parseFloat(item.total_billed_charges)}`,
        total_settlement_amount: `$${parseFloat(item.total_settlement_amount)}` || "$0.00",
        avg_settlement_percentage: `${((item.total_settlement_amount / item.total_billed_charges) * 100).toFixed(2)}%` || "0.00%",
    }));
};



