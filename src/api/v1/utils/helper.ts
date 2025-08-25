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

    for (const row of rawData) {
        const date = row.visit_date || "Unknown Date";
        const locationName = row.location_name || "Unknown Location";

        const value = useRevenue
            ? `$${parseFloat(row.total_revenue || 0)}`
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


export function transformAttorneyData(apiData: any[]) {
    if (!apiData || apiData.length === 0) return [];

    const attorneyData = apiData
    const transformed = attorneyData.map((item: any) => {
        const transformedItem: any = { attorney: item.attorney };

        // Iterate over each key
        Object.keys(item).forEach((key) => {
            if (!key.startsWith('attorney')) {
                transformedItem[key] = item[key] === 0 ? '-' : item[key];
            }
        });

        return transformedItem;
    });

    return transformed;
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



// date checker 

export function isFullYearRange(startDate: Date, endDate: Date): boolean {
    const start = new Date(startDate);
    const end = new Date(endDate);

    const isSameYear = start.getUTCFullYear() === end.getUTCFullYear();
    const isStartJanFirst = start.getUTCMonth() === 0 && start.getUTCDate() === 1;

    return isSameYear && isStartJanFirst;
}

// export function isFullYearOrMoreThanMonth(startDate: Date, endDate: Date): boolean {
//     const start = new Date(startDate);
//     const end = new Date(endDate);
//     const now = new Date();

//     const isSameYear = start.getUTCFullYear() === end.getUTCFullYear();
//     const isStartJanFirst = start.getUTCMonth() === 0 && start.getUTCDate() === 1;
//     const isEndDec31 = end.getUTCMonth() === 11 && end.getUTCDate() === 31;

//     console.log(isStartJanFirst, now, end, "django");
//     // ✅ Case 1: Current year, Jan 1 -> today
//     if (
//         isSameYear &&
//         start.getUTCFullYear() === now.getUTCFullYear() &&
//         isStartJanFirst &&
//         end <= now
//     ) {

//         console.log("yahan se data aa rha hy ")
//         return true;
//     }

//     // ✅ Case 2: Non-current year, Jan 1 -> Dec 31
//     if (isSameYear && isStartJanFirst && isEndDec31) {
//         return true;
//     }

//     // ✅ Case 3: ≤ 30 days but not in the same month
//     const diffInMs = end.getTime() - start.getTime();
//     const diffInDays = diffInMs / (1000 * 60 * 60 * 24);

//     if (diffInDays <= 30) {
//         const isSameMonth =
//             start.getUTCFullYear() === end.getUTCFullYear() &&
//             start.getUTCMonth() === end.getUTCMonth();
//         if (!isSameMonth) {
//             return true;
//         }
//     }

//     // ❌ Otherwise
//     return false;
// }

function toLocalDateOnly(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

export function isFullYearOrMoreThanMonth(startDate: Date, endDate: Date): boolean {
  const start = toLocalDateOnly(new Date(startDate));
  const end = toLocalDateOnly(new Date(endDate));

  const diffInDays = (end.getTime() - start.getTime()) / (1000 * 60 * 60 * 24);
  const monthDiff = (end.getFullYear() - start.getFullYear()) * 12 + (end.getMonth() - start.getMonth());

  return diffInDays > 30 || monthDiff >= 1;
}